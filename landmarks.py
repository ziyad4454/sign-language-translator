"""Shared code for recording data, training and live translation.

Everything that turns a camera frame into model input lives here, so a model sees
features computed exactly the same way live as it did during training. If you
change how features are computed, re-record the data in data/.

A frame's features describe up to two hands relative to the signer's body: the
point between the shoulders is the origin and the shoulder width is one unit.
Many signs differ mainly in where the hand is (forehead, mouth, chest), which hand
landmarks on their own can't tell.
"""

import csv
import time
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

PROJECT_DIR = Path(__file__).resolve().parent
DATA_DIR = PROJECT_DIR / "data"
MODEL_DIR = PROJECT_DIR / "model"
MODEL_URLS = {
    "hand_landmarker.task": "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
    "hand_landmarker/float16/latest/hand_landmarker.task",
    "pose_landmarker_lite.task": "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_lite/float16/latest/pose_landmarker_lite.task",
}

NUM_LANDMARKS = 21
HAND_FEATURES = NUM_LANDMARKS * 3  # x, y, z per landmark
FEATURES_PER_FRAME = 2 * HAND_FEATURES + 2  # two hand slots, then a "hand visible" flag per slot

# A dynamic sample is two seconds of movement, stored as 30 evenly spaced frames.
# Signs in the Saudi Sign Language dictionary's videos take 1.3 to 1.9 seconds.
SEQUENCE_SECONDS = 2.0
SEQUENCE_FRAMES = 30
SEQUENCE_FEATURES = SEQUENCE_FRAMES * FEATURES_PER_FRAME

# A clip is thrown away if the body goes undetected for longer than this.
MAX_GAP_SECONDS = 0.2

# MediaPipe pose landmark numbers.
LEFT_SHOULDER, RIGHT_SHOULDER, LEFT_WRIST, RIGHT_WRIST = 11, 12, 15, 16

SLOT_COLORS = [(255, 190, 0), (0, 140, 255)]  # BGR: slot 0 (right hand) blue, slot 1 (left hand) orange


@dataclass
class TrackedFrame:
    """What SignTracker found in one frame. Coordinates are in image-height units:
    pixel positions divided by the frame height.

    shoulders: (2, 2) array holding the signer's two shoulders, or None when no
        body was found.
    hands: two slots, each a (21, 3) array or None. Slot 0 is the signer's right
        hand and slot 1 the left: each hand goes to the slot of the nearest wrist
        found by the pose model, so it keeps its slot even when the hands cross.
        Without a body, hands are listed in the order MediaPipe found them.
    """

    shoulders: np.ndarray | None
    hands: list

    @property
    def hand_count(self):
        return sum(hand is not None for hand in self.hands)


class SignTracker:
    """Finds the signer's shoulders (MediaPipe PoseLandmarker) and up to two hands
    (MediaPipe HandLandmarker) in each video frame.

    Feed it mirrored frames (see read_mirrored_frame) both when recording and when
    translating, so left and right stay consistent.
    """

    def __init__(self, min_detection_confidence=0.6):
        # Imported here rather than at the top so train_model.py can use this module
        # without loading MediaPipe, which is slow to import and unused in training.
        import mediapipe as mp
        from mediapipe.tasks.python import vision
        from mediapipe.tasks.python.core.base_options import BaseOptions

        def model(filename):
            path = MODEL_DIR / filename
            if not path.exists():
                raise RuntimeError(f"Missing model/{filename}. Download it from {MODEL_URLS[filename]}")
            # Passed as bytes rather than a path: given a file path containing
            # non-English characters (like this project's Desktop folder), MediaPipe
            # crashes the whole program instead of loading the model.
            return BaseOptions(model_asset_buffer=path.read_bytes())

        # VIDEO mode follows the body and hands from one frame to the next and only
        # re-runs full detection when tracking is lost, which is faster and steadier.
        self._hands = vision.HandLandmarker.create_from_options(
            vision.HandLandmarkerOptions(
                base_options=model("hand_landmarker.task"),
                running_mode=vision.RunningMode.VIDEO,
                num_hands=2,
                min_hand_detection_confidence=min_detection_confidence,
            )
        )
        self._pose = vision.PoseLandmarker.create_from_options(
            vision.PoseLandmarkerOptions(
                base_options=model("pose_landmarker_lite.task"),
                running_mode=vision.RunningMode.VIDEO,
                min_pose_detection_confidence=min_detection_confidence,
            )
        )
        self._mp = mp
        self._connections = [(c.start, c.end) for c in vision.HandLandmarksConnections.HAND_CONNECTIONS]
        self._last_timestamp_ms = -1

    def find(self, frame_bgr, timestamp_ms=None):
        """Return a TrackedFrame for one mirrored BGR frame. Pass timestamp_ms when
        reading a video file, so tracking follows the video's own timing rather than
        how fast the file is processed."""
        height, width = frame_bgr.shape[:2]
        aspect = width / height
        image = self._mp.Image(image_format=self._mp.ImageFormat.SRGB, data=cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB))
        if timestamp_ms is None:
            timestamp_ms = int(time.monotonic() * 1000)
        # VIDEO mode requires every timestamp to be later than the one before.
        timestamp_ms = max(timestamp_ms, self._last_timestamp_ms + 1)
        self._last_timestamp_ms = timestamp_ms

        hands = [_to_array(hand, aspect) for hand in self._hands.detect_for_video(image, timestamp_ms).hand_landmarks]
        poses = self._pose.detect_for_video(image, timestamp_ms).pose_landmarks
        if not poses:
            return TrackedFrame(None, (hands + [None, None])[:2])
        body = _to_array(poses[0], aspect)[:, :2]
        # Frames are mirrored, so the pose model's LEFT_* landmarks land on the
        # signer's right side: a raised right hand was measured nearest LEFT_WRIST.
        slots = _assign_hands(hands, [body[LEFT_WRIST], body[RIGHT_WRIST]])
        return TrackedFrame(body[[LEFT_SHOULDER, RIGHT_SHOULDER]], slots)

    def draw(self, frame_bgr, tracked):
        """Draw the shoulder line and both hand skeletons onto the frame."""
        # Coordinates are in image-height units, so multiplying by the frame height
        # gives pixel positions.
        height = frame_bgr.shape[0]
        if tracked.shoulders is not None:
            first, second = ((int(x), int(y)) for x, y in tracked.shoulders * height)
            cv2.line(frame_bgr, first, second, (200, 200, 200), 2, cv2.LINE_AA)
        for slot, hand in enumerate(tracked.hands):
            if hand is None:
                continue
            pixels = [(int(x), int(y)) for x, y in hand[:, :2] * height]
            for start, end in self._connections:
                cv2.line(frame_bgr, pixels[start], pixels[end], SLOT_COLORS[slot], 2, cv2.LINE_AA)
            for pixel in pixels:
                cv2.circle(frame_bgr, pixel, 3, (255, 255, 255), -1, cv2.LINE_AA)

    def close(self):
        self._hands.close()
        self._pose.close()


def _to_array(points, aspect):
    """MediaPipe landmarks -> (n, 3) array in image-height units.

    MediaPipe divides x by the image width but y by the image height, so on a 4:3
    frame one unit of x is longer than one unit of y. Rescaling x (and z, which
    MediaPipe puts on the same scale as x) keeps shapes and distances the same
    whatever the camera's aspect ratio, e.g. a desktop webcam versus a browser stream.
    """
    return np.array([[p.x * aspect, p.y, p.z * aspect] for p in points], dtype=np.float32)


def _assign_hands(hands, wrists):
    """Put each hand in the slot whose pose wrist is nearest: slot i matches wrists[i]."""
    slots = [None, None]
    if len(hands) == 1:
        distances = [np.linalg.norm(hands[0][0, :2] - wrist) for wrist in wrists]
        slots[int(np.argmin(distances))] = hands[0]
    elif len(hands) >= 2:
        a, b = hands[:2]
        straight = np.linalg.norm(a[0, :2] - wrists[0]) + np.linalg.norm(b[0, :2] - wrists[1])
        swapped = np.linalg.norm(a[0, :2] - wrists[1]) + np.linalg.norm(b[0, :2] - wrists[0])
        slots = [a, b] if straight <= swapped else [b, a]
    return slots


def frame_features(tracked):
    """TrackedFrame -> FEATURES_PER_FRAME numbers, or None when no body was found.

    Each hand's 21 landmarks are measured from the point between the shoulders and
    divided by the shoulder width, so the numbers capture both the hand's shape and
    where it is relative to the body, whatever the distance from the camera. A
    missing hand is all zeros, with its visible flag at 0.
    """
    if tracked.shoulders is None:
        return None
    scale = float(np.linalg.norm(tracked.shoulders[0] - tracked.shoulders[1]))
    if scale < 1e-6:
        return None
    origin = tracked.shoulders.mean(axis=0)
    features = np.zeros(FEATURES_PER_FRAME, dtype=np.float32)
    for slot, hand in enumerate(tracked.hands):
        if hand is None:
            continue
        relative = hand.copy()
        relative[:, :2] -= origin
        features[slot * HAND_FEATURES:(slot + 1) * HAND_FEATURES] = (relative / scale).reshape(-1)
        features[2 * HAND_FEATURES + slot] = 1.0
    return features


def resample_clip(timestamps, frames, start, end):
    """Turn per-frame features captured at uneven times into SEQUENCE_FRAMES evenly
    spaced frames covering start..end.

    Webcam frame rate changes with lighting and CPU load, so the same two-second
    sign can give 40 frames once and 60 the next. Taking the recorded frame nearest
    to each evenly spaced moment keeps a clip meaning "two seconds of movement"
    whatever the frame rate was. Nearest rather than interpolated, so a hand that
    appears or disappears isn't blended with the zeros of a missing hand.

    `frames` holds frame_features() results, with None where no body was found.
    Returns a (SEQUENCE_FRAMES, FEATURES_PER_FRAME) array, or None if the body went
    undetected for more than MAX_GAP_SECONDS anywhere in the clip, including its
    start and end.
    """
    kept = [(t, features) for t, features in zip(timestamps, frames) if features is not None]
    if len(kept) < 2:
        return None
    times = np.array([t for t, _ in kept], dtype=np.float64)
    if np.diff(np.concatenate(([start], times, [end]))).max() > MAX_GAP_SECONDS:
        return None
    targets = np.linspace(start, end, SEQUENCE_FRAMES)
    nearest = np.abs(times[None, :] - targets[:, None]).argmin(axis=1)
    return np.stack([kept[i][1] for i in nearest])


def hand_coverage(clip):
    """Fraction of a clip's frames in which at least one hand is visible."""
    return float((clip[:, 2 * HAND_FEATURES:].max(axis=1) > 0).mean())


def open_camera(index=0):
    camera = cv2.VideoCapture(index)
    if not camera.isOpened():
        raise RuntimeError(
            f"Could not open webcam {index}. Check that it's plugged in and not in use "
            "by another app (Zoom, Teams, OBS...), or try --camera 1."
        )
    # 1280x720 rather than 640x480: with a hand held still, fingertip positions jumped
    # about 30% less from frame to frame, at 29 instead of 30 frames per second.
    camera.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    return camera


def read_mirrored_frame(camera):
    """Read one frame flipped left-to-right, so the preview moves like a mirror.
    Returns None if the camera stopped delivering frames."""
    ok, frame = camera.read()
    return cv2.flip(frame, 1) if ok else None


def sample_kind(num_features):
    """Tell static from dynamic samples by row length."""
    if num_features == FEATURES_PER_FRAME:
        return "static"
    if num_features == SEQUENCE_FEATURES:
        return "dynamic"
    raise ValueError(
        f"a sample has {num_features} values; expected {FEATURES_PER_FRAME} (static) "
        f"or {SEQUENCE_FEATURES} (dynamic). Data recorded before the switch to two hands "
        "and body-relative features has to be recorded again."
    )


def append_sample(writer, gesture, features):
    writer.writerow([gesture, *(f"{value:.5f}" for value in features)])


def load_gesture_csv(path):
    """Read one data/<gesture>.csv. Returns (labels, samples), where samples is a
    float32 array with one row per sample."""
    labels, rows = [], []
    with open(path, newline="", encoding="utf-8") as file:
        for row in csv.reader(file):
            if row:
                labels.append(row[0])
                rows.append(row[1:])
    if not rows:
        return [], np.empty((0, 0), dtype=np.float32)
    lengths = {len(row) for row in rows}
    if len(lengths) > 1:
        raise ValueError(f"{path.name} mixes rows of different lengths: {sorted(lengths)}")
    return labels, np.array(rows, dtype=np.float32)
