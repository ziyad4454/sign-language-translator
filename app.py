"""Phase 3: the chat-style translator app.

Runs the camera, body and hand tracking, and the gesture model in the background, and
serves the Flutter app in flutter_app/: the live camera next to a chat of translated
words, in Arabic or English. The app also has an accuracy test: it asks for each sign
in turn, checks the word the translator shows, and saves the score to logs/.

    python app.py                        # opens http://127.0.0.1:8000 in the browser
    python app.py --video a.mp4 b.mp4    # loop video files instead of the webcam (for testing)

Build the Flutter app before the first run, and again after changing it: run
`flutter build web --no-tree-shake-icons` in flutter_app/ (see flutter_app/README.md
for why the flag is needed).

The app talks to this server through:
    /ws                     JSON: "setup" once, then "state" (status, hint and top
                            predictions) several times a second, and a "word" for each
                            translated word
    /ws/video               the camera picture, one JPEG per binary message
    POST /api/camera        turns the camera off (the app's camera button) or on again
    POST /api/test-results  saves a finished accuracy test to logs/

Every run also records the translator's decisions in logs/session-<date>-<time>.csv
(see SessionLog), so a review can be checked afterwards.

The server only listens on 127.0.0.1, so the app can't be opened from other computers.
"""

import argparse
import asyncio
import csv
import json
import mimetypes
import threading
import time
import webbrowser
from contextlib import asynccontextmanager
from datetime import datetime

import cv2
import numpy as np
import uvicorn
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import PlainTextResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

import landmarks
import predict_live

WEB_APP_DIR = landmarks.PROJECT_DIR / "flutter_app" / "build" / "web"
NOT_BUILT = "The Flutter app isn't built yet. In the flutter_app folder, run: flutter build web --no-tree-shake-icons"
LOGS_DIR = landmarks.PROJECT_DIR / "logs"
HOST = "127.0.0.1"
# On its own, the work for each frame takes about 27 ms (37 fps), but with the app open
# the translator ran at 22 fps. The picture is only there so the signer can see
# themselves, so it's sent smaller and less often, to leave more of the computer for
# tracking.
STREAM_WIDTH = 640  # the camera picture sent to the app is scaled down to this width
PICTURE_FPS = 15  # at most this many pictures a second are sent to the app
STATE_INTERVAL_SECONDS = 0.15  # how often the app receives the status and top predictions
CAMERA_OFF_INTERVAL_SECONDS = 0.2  # how often the status is refreshed while the camera is off
VIDEO_PAUSE_SECONDS = 2.5  # --video: hands-down pause after each file, so each sign is translated on its own
# Hints for the app, from the shoulders' width and place in the picture. The width is
# measured in picture heights: too small and the hands wander out of the picture, too
# large and the sign in front of the stomach is cut off.
FAR_SHOULDERS = 0.3
CLOSE_SHOULDERS = 0.75
SIDE_MARGIN = 0.25  # the shoulders' middle should stay in the middle half of the picture

# The Windows registry can map these extensions to the wrong type, and the browser
# needs the right one to load the Flutter app's scripts and WebAssembly properly.
mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("text/javascript", ".mjs")
mimetypes.add_type("application/wasm", ".wasm")


class Engine:
    """Runs frames through tracking and the model in a background thread, and keeps
    what the app needs: the latest picture, the current status and predictions, and
    every word shown so far. The camera can be turned off and on again; while it's off
    the camera is closed, so its light goes out."""

    def __init__(self, open_frames, labels, predict, log_path=None):
        self.labels = labels
        self._open_frames = open_frames  # returns a (time, mirrored frame) iterator
        self._predict = predict
        self._log_path = log_path  # the SessionLog file, or None for no log
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._camera_on = threading.Event()
        self._camera_on.set()
        self._thread = threading.Thread(target=self._run, name="translator", daemon=True)
        self._picture, self._picture_number = None, 0
        self._state = {"status": "starting", "top": [], "fps": 0.0, "error": None, "camera": True, "hint": None}
        self._words = []

    def start(self):
        self._thread.start()

    def stop(self):
        self._stop.set()
        self._camera_on.set()  # so a waiting thread wakes up and ends
        self._thread.join(timeout=5)

    def set_camera(self, on):
        """Turn the camera on, or off to close it."""
        if on:
            self._camera_on.set()
        else:
            self._camera_on.clear()

    def camera_on(self):
        return self._camera_on.is_set()

    def picture(self):
        with self._lock:
            return self._picture_number, self._picture

    def state(self):
        with self._lock:
            return dict(self._state)

    def words_after(self, count):
        """Returns (number of words shown so far, the words after the first `count`)."""
        with self._lock:
            return len(self._words), self._words[count:]

    def _run(self):
        tracker, log = None, None
        try:
            tracker = landmarks.SignTracker()
            translator = predict_live.Translator(self._predict, self.labels)
            if self._log_path is not None:
                log = SessionLog(self._log_path, self.labels)
            while not self._stop.is_set():
                if not self._camera_on.is_set():
                    self._store(None, {"status": "camera_off", "top": [], "fps": 0.0, "error": None, "camera": False, "hint": None})
                    self._camera_on.wait(CAMERA_OFF_INTERVAL_SECONDS)
                    continue
                self._watch(tracker, translator, log)
        except Exception as error:  # shown in the app, instead of the translator silently stopping
            with self._lock:
                self._state = {"status": "error", "top": [], "fps": 0.0, "error": str(error), "camera": self.camera_on(), "hint": None}
        finally:
            if tracker is not None:
                tracker.close()
            if log is not None:
                log.close()

    def _watch(self, tracker, translator, log):
        """Track frames until the camera is turned off or the app stops."""
        frames = self._open_frames()
        fps, previous = 0.0, None
        try:
            for t, frame in frames:
                if self._stop.is_set() or not self._camera_on.is_set():
                    return
                tracked = tracker.find(frame, timestamp_ms=round(t * 1000))
                word = translator.add(t, landmarks.frame_features(tracked))
                if log is not None and translator.step is not None:
                    log.write(translator, tracked, word)
                tracker.draw(frame, tracked)
                now = time.monotonic()
                if previous is not None:
                    fps = 0.9 * fps + 0.1 / max(now - previous, 1e-3)
                previous = now
                state = {
                    "status": status_of(tracked),
                    "top": top_predictions(translator),
                    "fps": round(fps, 1),
                    "error": None,
                    "camera": True,
                    "hint": hint_for(tracked, frame.shape),
                }
                confidence = float(translator.probabilities[self.labels.index(word)]) if word else None
                self._store(encode_jpeg(frame), state, word, confidence)
            raise RuntimeError("The camera stopped sending frames.")
        finally:
            frames.close()

    def _store(self, picture, state, word=None, confidence=None):
        with self._lock:
            self._picture, self._picture_number = picture, self._picture_number + 1
            self._state = state
            if word:
                self._words.append(
                    {"label": word, "confidence": round(confidence, 3), "time": datetime.now().strftime("%H:%M:%S")}
                )


class SessionLog:
    """Records every decision the translator makes (about 10 a second) in a CSV file,
    one row each:

    - time: this computer's clock, to match the accuracy test's "started" times
    - step: "predict", or "reset" when the last two seconds had no hands or a gap in
      the body tracking
    - body, hands: whether the shoulders were found (1/0), and how many hands, in that frame
    - one column per gesture: the model's probability (empty on a reset)
    - word: the word shown at that moment, if any

    Replaying the rows through different rules shows what those rules would have shown."""

    def __init__(self, path, labels):
        path.parent.mkdir(exist_ok=True)
        self._file = path.open("w", newline="", encoding="utf-8")
        self._writer = csv.writer(self._file)
        self._writer.writerow(["time", "step", "body", "hands", *labels, "word"])
        self._gestures = len(labels)

    def write(self, translator, tracked, word):
        if translator.step == "predict":
            probabilities = [f"{p:.4f}" for p in translator.probabilities]
        else:
            probabilities = [""] * self._gestures
        body = int(tracked.shoulders is not None)
        now = datetime.now().isoformat(timespec="milliseconds")
        self._writer.writerow([now, translator.step, body, tracked.hand_count, *probabilities, word or ""])
        self._file.flush()  # so the file can be read while the app is running

    def close(self):
        self._file.close()


def encode_jpeg(frame):
    height, width = frame.shape[:2]
    if width > STREAM_WIDTH:
        frame = cv2.resize(frame, (STREAM_WIDTH, round(height * STREAM_WIDTH / width)), interpolation=cv2.INTER_AREA)
    return cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 75])[1].tobytes()


def status_of(tracked):
    if tracked.shoulders is None:
        return "no_body"
    return "watching" if tracked.hand_count else "no_hands"


def hint_for(tracked, shape):
    """What the signer should change about where they sit, as a key the app turns into
    text: move_closer, move_back, center_yourself, or None when the seat is fine."""
    if tracked.shoulders is None:
        return None  # the status already says the head and shoulders aren't in view
    width = float(np.linalg.norm(tracked.shoulders[0] - tracked.shoulders[1]))
    if width < FAR_SHOULDERS:
        return "move_closer"
    if width > CLOSE_SHOULDERS:
        return "move_back"
    aspect = shape[1] / shape[0]  # the shoulders' x runs from 0 to this, y from 0 to 1
    middle = float(tracked.shoulders[:, 0].mean())
    if not SIDE_MARGIN * aspect <= middle <= (1 - SIDE_MARGIN) * aspect:
        return "center_yourself"
    return None


def top_predictions(translator, count=3):
    if translator.probabilities is None:
        return []
    order = np.argsort(translator.probabilities)[::-1][:count]
    return [[translator.labels[i], round(float(translator.probabilities[i]), 3)] for i in order]


def camera_frames(index):
    """Returns a function that opens the webcam and gives its (time, mirrored frame) stream."""

    def open_frames():
        camera = landmarks.open_camera(index)

        def frames():
            try:
                while (frame := landmarks.read_mirrored_frame(camera)) is not None:
                    yield time.monotonic(), frame
            finally:
                camera.release()

        return frames()

    return open_frames


def video_frames(paths):
    """Returns a function that gives an endless (time, mirrored frame) stream playing the
    videos in a loop at normal speed, with a hands-down pause after each one."""

    def open_frames():
        for path in paths:
            capture = cv2.VideoCapture(str(path))
            opened = capture.isOpened()
            capture.release()
            if not opened:
                raise RuntimeError(f"Could not open {path}")

        def frames():
            start, played = time.monotonic(), 0.0

            def at(seconds):
                delay = start + seconds - time.monotonic()
                if delay > 0:
                    time.sleep(delay)
                return seconds

            while True:
                for path in paths:
                    t, frame = 0.0, None
                    for t, frame in predict_live.frames_from_video(path):
                        yield at(played + t), frame
                    if frame is None:
                        continue
                    for k in range(1, round(VIDEO_PAUSE_SECONDS * 25) + 1):
                        yield at(played + t + k / 25), frame.copy()
                    played += t + VIDEO_PAUSE_SECONDS + 1 / 25

        return frames()

    return open_frames


def test_order(labels, translations):
    """The gestures the accuracy test asks for: those in labels_translation.json in that
    file's order, then any other gesture the model knows. Never "nothing"."""
    ordered = [label for label, text in translations.items() if text and label in labels]
    return ordered + [label for label in labels if label not in ordered and label != predict_live.NOTHING]


class Trial(BaseModel):
    expected: str
    started: datetime | None = None  # when the app asked for the sign, on this computer's clock
    shown: str | None = None
    seconds: float = Field(ge=0, le=600)


class TestResults(BaseModel):
    trials: list[Trial] = Field(min_length=1, max_length=100)


class CameraSwitch(BaseModel):
    on: bool


def create_app(engine, translations):
    @asynccontextmanager
    async def lifespan(app):
        engine.start()
        yield
        engine.stop()

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
    order = test_order(engine.labels, translations)

    @app.websocket("/ws/video")
    async def video(socket: WebSocket):
        await socket.accept()
        closed = asyncio.create_task(socket.receive())  # the app never sends anything, so this ends when it leaves
        sent, sent_at = 0, 0.0
        try:
            while not closed.done():
                number, picture = engine.picture()
                if picture is not None and number != sent and time.monotonic() - sent_at >= 1 / PICTURE_FPS:
                    sent, sent_at = number, time.monotonic()
                    # Waits while the app is still receiving earlier pictures, so a
                    # slow connection skips pictures instead of falling behind.
                    await socket.send_bytes(picture)
                else:
                    await asyncio.sleep(0.01)
        except (WebSocketDisconnect, RuntimeError):
            pass  # the app was closed or reloaded
        finally:
            closed.cancel()

    @app.websocket("/ws")
    async def events(socket: WebSocket):
        await socket.accept()
        await socket.send_json({"type": "setup", "labels": engine.labels, "translations": translations, "testOrder": order})
        seen, _ = engine.words_after(0)  # only words shown from now on
        try:
            while True:
                await socket.send_json({"type": "state", **engine.state()})
                seen, words = engine.words_after(seen)
                for word in words:
                    await socket.send_json({"type": "word", **word})
                await asyncio.sleep(STATE_INTERVAL_SECONDS)
        except (WebSocketDisconnect, RuntimeError):
            pass  # the app was closed or reloaded

    @app.post("/api/camera")
    async def switch_camera(switch: CameraSwitch):
        engine.set_camera(switch.on)
        return {"on": engine.camera_on()}

    @app.post("/api/test-results")
    async def save_test_results(results: TestResults):
        known = set(engine.labels)
        if any(t.expected not in known or (t.shown is not None and t.shown not in known) for t in results.trials):
            raise HTTPException(status_code=400, detail="unknown gesture name")
        LOGS_DIR.mkdir(exist_ok=True)
        stamp = datetime.now()
        path, suffix = LOGS_DIR / f"test-{stamp:%Y%m%d-%H%M%S}.json", 1
        while path.exists():
            path, suffix = LOGS_DIR / f"test-{stamp:%Y%m%d-%H%M%S}-{suffix}.json", suffix + 1
        correct = sum(t.expected == t.shown for t in results.trials)
        report = {
            "date": stamp.isoformat(timespec="seconds"),
            "correct": correct,
            "total": len(results.trials),
            "trials": [t.model_dump(mode="json") for t in results.trials],
        }
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        return {"file": f"logs/{path.name}", "correct": correct, "total": len(results.trials)}

    if (WEB_APP_DIR / "index.html").exists():
        # Added last, because it answers every address the routes above don't.
        app.mount("/", StaticFiles(directory=WEB_APP_DIR, html=True), name="app")
    else:

        @app.get("/")
        async def not_built():
            return PlainTextResponse(NOT_BUILT, status_code=503)

    return app


def parse_args():
    parser = argparse.ArgumentParser(description="Run the sign language translator app.")
    parser.add_argument("--camera", type=int, default=0, help="webcam index (default: 0)")
    parser.add_argument("--video", nargs="+", help="loop these video files instead of the webcam")
    parser.add_argument("--port", type=int, default=8000, help="port for the page (default: 8000)")
    parser.add_argument("--no-browser", action="store_true", help="don't open the page in the browser")
    return parser.parse_args()


def main():
    args = parse_args()
    labels, predict = predict_live.load_model()
    translations = (
        json.loads(predict_live.TRANSLATIONS_PATH.read_text(encoding="utf-8")) if predict_live.TRANSLATIONS_PATH.exists() else {}
    )
    open_frames = video_frames(args.video) if args.video else camera_frames(args.camera)
    log_path = LOGS_DIR / f"session-{datetime.now():%Y%m%d-%H%M%S}.csv"
    app = create_app(Engine(open_frames, labels, predict, log_path), translations)
    url = f"http://{HOST}:{args.port}"
    print(f"Sign translator: {url}  (Ctrl+C to stop)", flush=True)
    print(f"Recording the translator's decisions in logs/{log_path.name}", flush=True)
    if not (WEB_APP_DIR / "index.html").exists():
        print(NOT_BUILT, flush=True)
    if not args.no_browser:
        threading.Timer(2.0, webbrowser.open, args=(url,)).start()
    # The app's WebSockets stay open, so don't wait long for them on Ctrl+C.
    uvicorn.run(app, host=HOST, port=args.port, log_level="warning", timeout_graceful_shutdown=2)


if __name__ == "__main__":
    main()
