"""Record webcam samples of one sign into data/<gesture>.csv.

Dynamic sign (the hands move) - one sample per recording:
    python collect_data.py hello --dynamic
Static sign (hands held completely still) - one sample per captured frame:
    python collect_data.py <gesture>
See what's been recorded so far:
    python collect_data.py --list

Sit so your head, shoulders and stomach are in view: every sample is measured
relative to your shoulders. Each run appends to the gesture's file, so several
short sessions add up. Change your position, lighting and distance between
sessions: that variety is what lets the model recognise a sign when you aren't
sitting exactly the same way.

A dynamic recording lasts RECORD_SECONDS, longer than a sample, so a sign started a
little late still fits: the two seconds centred on the hands' movement are saved.

Each row is: gesture_name, then 128 numbers per frame (one frame for a static
sign, 30 frames covering two seconds for a dynamic sign). A frame holds x, y, z of
the 21 landmarks of each of two hands, measured from the point between the
shoulders in shoulder widths, then one "hand visible" flag per hand.

Keys: SPACE start/pause, Q or ESC quit. Samples are saved the moment they're taken.
"""

import argparse
import csv
import re
import sys
import time

import cv2
import numpy as np

import landmarks

STATIC_INTERVAL_SECONDS = 0.15  # gap between static samples so they aren't near-duplicates
GET_READY_SECONDS = 1.5  # pause before each dynamic recording, to lower the hands after the last sign
# A clip recorded exactly when the border turns red cuts off a sign that starts late, so
# each recording is longer than a clip, and the saved clip is centred on the movement,
# the way the dictionary clips are centred on the sign.
RECORD_SECONDS = 3.0
STILL_BELOW = 0.01  # shoulder widths per frame: a still hand's tracking jitter stays below this
MIN_HAND_COVERAGE = 0.5  # a sample needs a hand visible in at least half its frames...
NO_HAND_GESTURES = {"nothing"}  # ...except gestures that are about not signing
MIN_RECOMMENDED_SAMPLES = 30
H = landmarks.HAND_FEATURES

WINDOW_TITLE = "Collect data - SPACE start/pause, Q quit"
FONT = cv2.FONT_HERSHEY_SIMPLEX
WHITE = (255, 255, 255)
RED = (60, 60, 230)
YELLOW = (0, 210, 255)
GREY = (170, 170, 170)


def parse_args():
    parser = argparse.ArgumentParser(description="Record body-relative hand samples of one sign.")
    parser.add_argument("gesture", nargs="?", help="gesture name, e.g. hello or thank_you")
    parser.add_argument("--dynamic", action="store_true", help="the sign involves movement (records two-second clips)")
    parser.add_argument("--samples", type=int, default=40, help="samples to record this run (default: 40)")
    parser.add_argument("--camera", type=int, default=0, help="webcam index (default: 0)")
    parser.add_argument("--list", action="store_true", help="show recorded gestures and sample counts, then exit")
    args = parser.parse_args()
    if not args.list and not args.gesture:
        parser.error("give a gesture name, or use --list")
    if args.samples < 1:
        parser.error("--samples must be at least 1")
    return args


def main():
    args = parse_args()
    if args.list:
        print_summary()
        return

    gesture = args.gesture.lower()
    if not re.fullmatch(r"[a-z0-9_]+", gesture):
        sys.exit(
            "Use English letters, digits and _ in gesture names (e.g. thank_you). "
            "The Arabic text shown in the app is set separately."
        )
    kind = "dynamic" if args.dynamic else "static"
    path = landmarks.DATA_DIR / f"{gesture}.csv"

    previous = 0
    if path.exists():
        _, samples = landmarks.load_gesture_csv(path)
        previous = len(samples)
        if previous and landmarks.sample_kind(samples.shape[1]) != kind:
            other = "static" if args.dynamic else "dynamic"
            flag = "without" if args.dynamic else "with"
            sys.exit(
                f"data/{gesture}.csv already holds {other} samples. Record it as {other} "
                f"({flag} --dynamic), or delete the file to start over."
            )

    landmarks.DATA_DIR.mkdir(exist_ok=True)
    try:
        tracker = landmarks.SignTracker()
        camera = landmarks.open_camera(args.camera)
    except RuntimeError as error:
        sys.exit(str(error))
    try:
        with open(path, "a", newline="", encoding="utf-8") as file:
            recorded = record(camera, tracker, file, gesture, kind, args.samples, previous)
    finally:
        camera.release()
        tracker.close()
        cv2.destroyAllWindows()

    total = previous + recorded
    print(f"Saved {recorded} new {kind} samples to data/{gesture}.csv ({total} in total).")
    if total < MIN_RECOMMENDED_SAMPLES:
        print(f"Aim for at least {MIN_RECOMMENDED_SAMPLES} samples per gesture before training.")


def record(camera, tracker, file, gesture, kind, target, previous):
    """Show the camera and save samples until `target` are recorded or the user quits.
    Returns how many samples were saved."""
    writer = csv.writer(file)
    hands_required = gesture not in NO_HAND_GESTURES
    recorded = 0
    running = False
    next_static_at = 0.0
    ready_until = 0.0  # dynamic: end of the get-ready pause before the next recording
    clip_start = None  # dynamic: when the recording in progress started
    clip_times, clip_frames = [], []
    notice = ""

    def save(features):
        nonlocal recorded
        landmarks.append_sample(writer, gesture, features)
        file.flush()
        recorded += 1

    # Keep the window above other apps: started from a terminal or the Claude app,
    # it otherwise opens behind them.
    cv2.namedWindow(WINDOW_TITLE)
    cv2.setWindowProperty(WINDOW_TITLE, cv2.WND_PROP_TOPMOST, 1)
    while recorded < target:
        frame = landmarks.read_mirrored_frame(camera)
        if frame is None:
            print("The camera stopped sending frames.")
            break
        now = time.monotonic()
        tracked = tracker.find(frame)
        tracker.draw(frame, tracked)
        features = landmarks.frame_features(tracked)

        if not running:
            status, color = "PAUSED - press SPACE to start", YELLOW
        elif kind == "static":
            if features is None:
                status, color = "Body not in view - show head and shoulders", GREY
            elif hands_required and tracked.hand_count == 0:
                status, color = "No hand detected", GREY
            else:
                status, color = "RECORDING - move a little between samples", RED
                if now >= next_static_at:
                    save(features)
                    next_static_at = now + STATIC_INTERVAL_SECONDS
        else:
            if clip_start is None and now >= ready_until:
                clip_start, clip_times, clip_frames = now, [], []
            if clip_start is None:
                status, color = f"GET READY  {ready_until - now:.1f}s", YELLOW
            else:
                status, color = f"RECORDING - sign now  {max(0.0, clip_start + RECORD_SECONDS - now):.1f}s", RED
                clip_times.append(now)
                clip_frames.append(features)
                if now - clip_start >= RECORD_SECONDS:
                    clip = centred_clip(clip_times, clip_frames)
                    if clip is None:
                        notice = "Body went out of view - clip discarded, try again"
                    elif hands_required and landmarks.hand_coverage(clip) < MIN_HAND_COVERAGE:
                        notice = "Hands were barely visible - clip discarded, try again"
                    else:
                        save(clip.reshape(-1))
                        notice = ""
                    clip_start, ready_until = None, now + GET_READY_SECONDS

        draw_status(
            frame,
            [
                (f"{gesture} ({kind})   {recorded}/{target} this run   {previous + recorded} total", WHITE),
                (status, color),
                (notice, WHITE),
            ],
        )
        if color == RED:
            cv2.rectangle(frame, (0, 0), (frame.shape[1] - 1, frame.shape[0] - 1), RED, 6)
        cv2.imshow(WINDOW_TITLE, frame)

        key = cv2.waitKey(1) & 0xFF
        if key in (ord("q"), 27) or cv2.getWindowProperty(WINDOW_TITLE, cv2.WND_PROP_VISIBLE) < 1:
            break
        if key == ord(" "):
            running = not running
            clip_start, ready_until = None, now + GET_READY_SECONDS
            notice = ""
    return recorded


def centred_clip(times, frames):
    """The SEQUENCE_SECONDS of a recording centred on the hands' movement (on the
    middle of the recording if the hands didn't move), as a clip. None if the body
    went out of view during that part."""
    half = landmarks.SEQUENCE_SECONDS / 2
    center = movement_center(times, frames)
    if center is None:
        center = (times[0] + times[-1]) / 2
    center = min(max(center, times[0] + half), times[-1] - half)
    return landmarks.resample_clip(times, frames, center - half, center + half)


def movement_center(times, frames):
    """When the hands moved, on average: each moment between two frames weighted by
    how far the hands' landmarks moved then, ignoring jitter below STILL_BELOW. None
    if no hand moved."""
    moments, amounts = [], []
    for t0, t1, before, after in zip(times, times[1:], frames, frames[1:]):
        if before is None or after is None:
            continue
        amount = 0.0
        for slot in range(2):
            if before[2 * H + slot] > 0 and after[2 * H + slot] > 0:
                start = before[slot * H:(slot + 1) * H].reshape(-1, 3)[:, :2]
                end = after[slot * H:(slot + 1) * H].reshape(-1, 3)[:, :2]
                amount += max(0.0, float(np.linalg.norm(end - start, axis=1).mean()) - STILL_BELOW)
        moments.append((t0 + t1) / 2)
        amounts.append(amount)
    total = sum(amounts)
    return float(np.dot(moments, amounts) / total) if total > 0 else None


def draw_status(frame, lines):
    y = 30
    for text, color in lines:
        if not text:
            continue
        (width, height), _ = cv2.getTextSize(text, FONT, 0.6, 2)
        cv2.rectangle(frame, (8, y - height - 8), (16 + width, y + 8), (0, 0, 0), -1)
        cv2.putText(frame, text, (12, y), FONT, 0.6, color, 2, cv2.LINE_AA)
        y += height + 22


def print_summary():
    paths = sorted(landmarks.DATA_DIR.rglob("*.csv"))
    if not paths:
        print("No gestures recorded yet.")
        return
    for path in paths:
        _, samples = landmarks.load_gesture_csv(path)
        kind = landmarks.sample_kind(samples.shape[1]) if len(samples) else "-"
        name = path.relative_to(landmarks.DATA_DIR).with_suffix("").as_posix()
        print(f"{name:<24}{kind:<9}{len(samples):>4} samples")


if __name__ == "__main__":
    main()
