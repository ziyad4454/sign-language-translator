"""Phase 2: translate signs live from the webcam.

Tracks the body and hands in every frame (landmarks.SignTracker) and, every few
frames, feeds the last two seconds of movement to the trained model. A word is only
shown once the same prediction has stayed confident for a moment (STABLE_SECONDS), so
one sign isn't reported many times per second.

    python predict_live.py
    python predict_live.py --video a.mp4 b.mp4 --headless   # test on video files

Keys: Q or ESC quit, C clear the translated words.
"""

import argparse
import json
import os
import sys
import time
from collections import deque

import cv2
import numpy as np

import landmarks

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")  # hide TensorFlow's start-up log lines

LABELS_PATH = landmarks.MODEL_DIR / "labels.json"
MODEL_PATH = landmarks.MODEL_DIR / "gesture_lstm.keras"
TRANSLATIONS_PATH = landmarks.PROJECT_DIR / "labels_translation.json"
NOTHING = "nothing"

PREDICT_EVERY = 3  # frames between predictions: about 10 a second at 30 fps
CONFIDENCE = 0.7  # below this a prediction counts as "not sure"
# How long predictions must hold. These rules were first tuned as counts of predictions:
# 8 confident ones in a row to show a word, and 10 "nothing" in a row before it can be
# shown again, plus a cooldown. Replaying the first live webcam test, longer runs and the
# cooldown cut quick repeats of a word from 7 to 2-4; on the dictionary videos, 10 in a row
# missed the "no" video while 8 found all 9 signs. But a count takes longer at a lower
# frame rate: in the chat app the webcam ran at 22 fps, so 8 in a row took 1.1 s, and signs
# the model recognised for well under a second were never shown. Measured in seconds, on
# the 9 dictionary sign videos and 23 other signs: 0.65 s found all 9 signs with 2 wrong
# words, 0.75 s all 9 with 1 (the same as 8 in a row), and 0.85 s only 8. Replaying that
# camera session, 0.75 s showed 3 words where 8 in a row showed 2.
STABLE_SECONDS = 0.75  # the same confident prediction held this long before its word is shown
NOTHING_TO_RESET_SECONDS = 0.85  # "nothing" held this long (about 10 predictions) before the last word can be shown again
SAME_WORD_COOLDOWN_SECONDS = 4.0  # never show the same word twice within this time
VIDEO_TAIL_SECONDS = 1.0  # after a video file ends, keep its last frame this long, like a signer standing still

WINDOW_TITLE = "Sign translator - Q quit, C clear"
FONT = cv2.FONT_HERSHEY_SIMPLEX
WHITE, GREY, GREEN, YELLOW = (255, 255, 255), (170, 170, 170), (80, 220, 80), (0, 210, 255)


class Translator:
    """Turns a stream of frame features into translated words.

    Every PREDICT_EVERY frames it classifies the last SEQUENCE_SECONDS of movement. A
    word is emitted once the same gesture has been the top prediction, at CONFIDENCE
    or above, for STABLE_SECONDS without a break. After that, the same word waits until
    "nothing" has been predicted for NOTHING_TO_RESET_SECONDS or the hands leave the
    view, and never comes back within SAME_WORD_COOLDOWN_SECONDS. That way one sign, or
    a brief flicker in the middle of it, isn't shown twice.
    """

    def __init__(self, predict, labels):
        self.predict = predict
        self.labels = labels
        self.times, self.frames = deque(), deque()
        self.count = 0
        self.candidate, self.candidate_since = None, None  # the current confident top prediction, and since when
        self.last_emitted, self.nothing_since = None, None
        self.shown_at = {}  # label -> time it was last shown
        self.probabilities = None  # the latest prediction, for display
        self.step = None  # what the latest add() did: None, "reset" or "predict"

    def add(self, t, features):
        """Add one frame's features (None when no body was found). Returns the label
        of a newly recognised gesture, or None."""
        self.step = None
        self.times.append(t)
        self.frames.append(features)
        while t - self.times[0] > landmarks.SEQUENCE_SECONDS + 0.5:
            self.times.popleft()
            self.frames.popleft()
        self.count += 1
        if self.count % PREDICT_EVERY or t - self.times[0] < landmarks.SEQUENCE_SECONDS:
            return None

        clip = landmarks.resample_clip(self.times, self.frames, t - landmarks.SEQUENCE_SECONDS, t)
        if clip is None or landmarks.hand_coverage(clip) == 0:
            # Body out of view or no hands for two seconds: start fresh, and allow
            # the last word to be signed again once its cooldown is over.
            self.step = "reset"
            self.probabilities = None
            self.candidate, self.candidate_since = None, None
            self.last_emitted, self.nothing_since = None, None
            return None

        self.probabilities = self.predict(clip)
        self.step = "predict"
        top = int(np.argmax(self.probabilities))
        label = self.labels[top]
        if self.probabilities[top] < CONFIDENCE:
            self.candidate = None
            return None
        if label != self.candidate:
            self.candidate, self.candidate_since = label, t
        if label == NOTHING:
            if self.nothing_since is None:
                self.nothing_since = t
            if t - self.nothing_since >= NOTHING_TO_RESET_SECONDS:
                self.last_emitted = None
            return None
        self.nothing_since = None
        held = t - self.candidate_since
        recently_shown = t - self.shown_at.get(label, -np.inf) < SAME_WORD_COOLDOWN_SECONDS
        if held >= STABLE_SECONDS and label != self.last_emitted and not recently_shown:
            self.last_emitted = label
            self.shown_at[label] = t
            return label
        return None


def parse_args():
    parser = argparse.ArgumentParser(description="Translate signs from the webcam into words.")
    parser.add_argument("--camera", type=int, default=0, help="webcam index (default: 0)")
    parser.add_argument("--video", nargs="+", help="translate these video files instead of the webcam")
    parser.add_argument("--headless", action="store_true", help="with --video: print the words without opening a window")
    return parser.parse_args()


def main():
    args = parse_args()
    labels, predict = load_model()
    translations = json.loads(TRANSLATIONS_PATH.read_text(encoding="utf-8")) if TRANSLATIONS_PATH.exists() else {}
    if args.video:
        for path in args.video:
            words = run(frames_from_video(path), predict, labels, translations, show=not args.headless)
            print(f"{path}: {', '.join(words) or '(nothing translated)'}", flush=True)
        return
    try:
        camera = landmarks.open_camera(args.camera)
    except RuntimeError as error:
        sys.exit(str(error))
    try:
        run(frames_from_camera(camera), predict, labels, translations, show=True)
    finally:
        camera.release()


def load_model():
    """Load the dynamic gesture model. Returns (labels, predict), where predict maps
    one clip to an array of probabilities in label order."""
    if not LABELS_PATH.exists() or not MODEL_PATH.exists():
        sys.exit("No trained model yet. Run train_model.py first.")
    info = json.loads(LABELS_PATH.read_text(encoding="utf-8"))
    if (info.get("sequence_frames"), info.get("features_per_frame")) != (landmarks.SEQUENCE_FRAMES, landmarks.FEATURES_PER_FRAME):
        sys.exit("The trained model doesn't match the current features. Run train_model.py again.")
    if "dynamic_labels" not in info:
        sys.exit("The trained model has no dynamic gestures. Live translation only uses dynamic gestures.")
    import keras

    model = keras.models.load_model(MODEL_PATH)
    return info["dynamic_labels"], lambda clip: np.asarray(model(clip[None].astype(np.float32), training=False))[0]


def frames_from_camera(camera):
    while (frame := landmarks.read_mirrored_frame(camera)) is not None:
        yield time.monotonic(), frame


def frames_from_video(path):
    capture = cv2.VideoCapture(str(path))
    if not capture.isOpened():
        sys.exit(f"Could not open {path}")
    fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
    index, frame = 0, None
    try:
        while True:
            ok, next_frame = capture.read()
            if not ok:
                break
            frame = cv2.flip(next_frame, 1)  # mirrored like the webcam preview
            yield index / fps, frame
            index += 1
    finally:
        capture.release()
    # A live signer keeps standing there after a sign, so give a sign near the end of
    # the file the same chance of a full two-second window.
    for _ in range(round(VIDEO_TAIL_SECONDS * fps) if frame is not None else 0):
        yield index / fps, frame.copy()
        index += 1


def run(frames, predict, labels, translations, show):
    """Translate a stream of (time, mirrored frame) pairs. Returns the recognised labels."""
    tracker = landmarks.SignTracker()
    translator = Translator(predict, labels)
    words = []
    if show:
        cv2.namedWindow(WINDOW_TITLE)
        cv2.setWindowProperty(WINDOW_TITLE, cv2.WND_PROP_TOPMOST, 1)
    try:
        for t, frame in frames:
            tracked = tracker.find(frame, timestamp_ms=round(t * 1000))
            word = translator.add(t, landmarks.frame_features(tracked))
            if word:
                words.append(word)
                confidence = translator.probabilities[labels.index(word)]
                print(f"{t:7.2f}s  {english(word, translations)}  |  {arabic(word, translations)}  ({confidence:.0%})", flush=True)
            if not show:
                continue
            tracker.draw(frame, tracked)
            draw_overlay(frame, tracked, translator, words, translations)
            cv2.imshow(WINDOW_TITLE, frame)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27) or cv2.getWindowProperty(WINDOW_TITLE, cv2.WND_PROP_VISIBLE) < 1:
                break
            if key == ord("c"):
                words.clear()
    finally:
        tracker.close()
        if show:
            cv2.destroyAllWindows()
    return words


def draw_overlay(frame, tracked, translator, words, translations):
    if tracked.shoulders is None:
        lines = [("Body not in view - show head and shoulders", GREY)]
    elif tracked.hand_count == 0:
        lines = [("No hands detected", GREY)]
    else:
        lines = [("Watching...", GREEN)]
    if translator.probabilities is not None:
        for i in np.argsort(translator.probabilities)[::-1][:3]:
            p = translator.probabilities[i]
            name = english(translator.labels[i], translations) or translator.labels[i]
            lines.append((f"{name}  {p:.0%}", YELLOW if p >= CONFIDENCE else WHITE))
    y = 30
    for text, color in lines:
        draw_text(frame, text, (12, y), color)
        y += 32
    transcript = "  ".join(english(word, translations) for word in words[-5:])
    if transcript:
        draw_text(frame, transcript, (12, frame.shape[0] - 20), WHITE, scale=0.8)


def draw_text(frame, text, origin, color, scale=0.6):
    (width, height), _ = cv2.getTextSize(text, FONT, scale, 2)
    x, y = origin
    cv2.rectangle(frame, (x - 4, y - height - 8), (x + width + 4, y + 8), (0, 0, 0), -1)
    cv2.putText(frame, text, (x, y), FONT, scale, color, 2, cv2.LINE_AA)


def english(label, translations):
    entry = translations.get(label) or {}
    return entry.get("en") or label.replace("_", " ")


def arabic(label, translations):
    entry = translations.get(label) or {}
    return entry.get("ar") or label


if __name__ == "__main__":
    main()
