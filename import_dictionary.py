"""Build training data from the videos of the official Saudi Sign Language dictionary.

Instead of recording every sign yourself, this takes each sign's video from the
dictionary of the Saudi Association for Hearing Impairment (https://sshi.sa),
tracks the signer's body and hands the same way collect_data.py tracks the webcam,
and writes varied two-second clips to data/dictionary/<gesture>.csv.

    python import_dictionary.py               # 120 clips per gesture
    python import_dictionary.py --clips 200

dictionary_signs.json lists which dictionary videos belong to which gesture. To add
a gesture, add its dictionary word ids there, run this again and retrain. Missing
videos are downloaded into the --videos folder (a few hundred KB each).

Each gesture has only one or two real performances in the dictionary, so every clip
is one of them varied (overall speed, pace within the sign, timing, position, size,
tilt, hand size, the hands' path, depth, tracking noise) to stand in for different
people and sessions. That is not the same as many real performances: test the
trained model live on the webcam. The "nothing" gesture is built from other
dictionary signs plus clips with no hands in view, so the model learns not to
translate those.
"""

import argparse
import csv
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

import cv2
import numpy as np

import landmarks

MANIFEST_PATH = landmarks.PROJECT_DIR / "dictionary_signs.json"
OUT_DIR = landmarks.DATA_DIR / "dictionary"
API_URL = "https://sshi.sa/api"
NOTHING = "nothing"
EMPTY_SHARE = 0.2  # share of "nothing" clips with no hands in view at all
H = landmarks.HAND_FEATURES

# The variation is wide on purpose. Trained on one or two performances per sign, the
# model otherwise learns those exact movements and misses the same sign done a little
# differently. When whole videos were left out of training, the unseen "please" and
# "help" videos were recognised in 90% of test clips with narrow variation (40 clips)
# and in all of them with these settings (120 clips).
DEFAULT_CLIPS = 120
CENTER_JITTER_SECONDS = 0.45  # where in the two-second window the sign sits
SPEED_RANGE = (0.65, 1.5)  # > 1: the sign performed faster
TIME_WARP = 0.12  # pace changes within the sign


def parse_args():
    parser = argparse.ArgumentParser(description="Build training clips from the Saudi Sign Language dictionary videos.")
    parser.add_argument("--clips", type=int, default=DEFAULT_CLIPS, help=f"clips per gesture (default: {DEFAULT_CLIPS})")
    parser.add_argument(
        "--videos",
        type=Path,
        default=Path.home() / ".sign-translator" / "dictionary_videos",
        help="folder the videos are downloaded to and read from (default: ~/.sign-translator/dictionary_videos)",
    )
    parser.add_argument("--seed", type=int, default=0, help="random seed, so every run produces the same clips")
    return parser.parse_args()


def main():
    args = parse_args()
    gestures = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))["gestures"]
    rng = np.random.default_rng(args.seed)
    args.videos.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    sources = {}
    for gesture, words in gestures.items():
        performances = []
        for word_id in words:
            times, features = extract(video_path(word_id, args.videos))
            span = sign_span(times, features)
            if span is None:
                print(f"  {gesture}: no hands found in video {word_id}, skipped")
                continue
            performances.append((word_id, times, features, span))
        if not performances:
            sys.exit(f"No usable video for {gesture}.")

        empty = round(args.clips * EMPTY_SHARE) if gesture == NOTHING else 0
        clips, origins = [], []
        for k in range(args.clips - empty):
            word_id, times, features, span = performances[k % len(performances)]
            center = (span[0] + span[1]) / 2 + rng.uniform(-CENTER_JITTER_SECONDS, CENTER_JITTER_SECONDS)
            clip = clip_at(times, features, center, speed=rng.uniform(*SPEED_RANGE), rng=rng)
            clips.append(vary(clip, rng))
            origins.append(word_id)
        for _ in range(empty):
            clips.append(np.zeros((landmarks.SEQUENCE_FRAMES, landmarks.FEATURES_PER_FRAME), np.float32))
            origins.append("no hands")

        with open(OUT_DIR / f"{gesture}.csv", "w", newline="", encoding="utf-8") as file:
            writer = csv.writer(file)
            for clip in clips:
                landmarks.append_sample(writer, gesture, clip.reshape(-1))
        sources[gesture] = origins
        extra = f" + {empty} with no hands" if empty else ""
        print(f"{gesture:<10} {len(clips)} clips from {len(performances)} video(s){extra}")

    (OUT_DIR / "sources.json").write_text(json.dumps(sources, indent=1), encoding="utf-8")
    print("Wrote data/dictionary/<gesture>.csv, plus data/dictionary/sources.json listing the video behind each row.")


def video_path(word_id, videos_dir):
    """Path of a dictionary word's video, downloading it first if it isn't there yet."""
    path = videos_dir / f"{word_id}.mp4"
    if path.exists():
        return path
    with urllib.request.urlopen(f"{API_URL}/words/{word_id}", timeout=60) as response:
        info = json.load(response)["info"]
    print(f"  downloading video {word_id} ({info['wordAr']})")
    request = urllib.request.Request(
        f"{API_URL}/file/{urllib.parse.quote(info['video'])}", headers={"User-Agent": "Mozilla/5.0"}
    )
    part = path.with_suffix(".part")
    with urllib.request.urlopen(request, timeout=120) as response, open(part, "wb") as file:
        file.write(response.read())
    part.replace(path)
    return path


def extract(path):
    """Track a video the way collect_data.py tracks the webcam. Returns the frame
    times in seconds and each frame's features (None where no body was found)."""
    tracker = landmarks.SignTracker()  # a fresh tracker per video, so tracking doesn't carry over
    capture = cv2.VideoCapture(str(path))
    fps = capture.get(cv2.CAP_PROP_FPS) or 25.0
    times, features = [], []
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            t = len(times) / fps
            # Mirrored like the webcam preview: the dictionary films the signer from
            # the front, so flipping puts the signer's right hand where a webcam
            # user's right hand appears.
            tracked = tracker.find(cv2.flip(frame, 1), timestamp_ms=round(t * 1000))
            times.append(t)
            features.append(landmarks.frame_features(tracked))
    finally:
        capture.release()
        tracker.close()

    flags = np.array([f[2 * H:] for f in features if f is not None])
    if len(flags) and flags[:, 1].sum() > 2 * flags[:, 0].sum():
        # Signed with the left hand (or the video itself is mirrored): mirror it, so
        # every performance uses the right hand like the rest of the data.
        features = [mirror(f) for f in features]
        print(f"  video {path.stem}: signed with the left hand, mirrored to the right")
    return np.array(times), features


def mirror(features):
    """Left-right mirror of one frame's features: swap the hand slots and flip x."""
    if features is None:
        return None
    hands = features[:2 * H].reshape(2, landmarks.NUM_LANDMARKS, 3).copy()
    hands[..., 0] *= -1
    mirrored = features.copy()
    mirrored[:2 * H] = hands[::-1].reshape(-1)
    mirrored[2 * H:] = features[2 * H:][::-1]
    return mirrored


def sign_span(times, features):
    """First and last moment a hand is visible, or None if hands never appear."""
    visible = [i for i, f in enumerate(features) if f is not None and f[2 * H:].max() > 0]
    return (times[visible[0]], times[visible[-1]]) if visible else None


def clip_at(times, features, center, speed, rng=None):
    """A SEQUENCE_FRAMES clip centered on `center` seconds into the video.

    speed > 1 squeezes more of the video into the clip, as if the sign were performed
    faster. Given rng, the pace also changes a little within the clip, the way a
    signer speeds up or slows down part of a sign. Moments before the video starts or
    after it ends repeat its first or last frame, where the signer stands still.
    """
    length = landmarks.SEQUENCE_SECONDS * speed
    steps = np.linspace(0, 1, landmarks.SEQUENCE_FRAMES)
    if rng is not None:
        knots = np.sort(np.clip(np.array([1 / 3, 2 / 3]) + rng.uniform(-TIME_WARP, TIME_WARP, 2), 0.05, 0.95))
        steps = np.interp(steps, [0, 1 / 3, 2 / 3, 1], [0, knots[0], knots[1], 1])
    targets = center - length / 2 + steps * length
    body = [i for i, f in enumerate(features) if f is not None]
    nearest = np.abs(times[body][None, :] - targets[:, None]).argmin(axis=1)
    return np.stack([features[body[i]] for i in nearest])


def vary(clip, rng):
    """Random changes of the kind a different person, camera or session causes."""
    clip = clip.copy()
    frames = len(clip)
    angle = np.radians(rng.uniform(-15, 15))  # body or camera tilt
    rotation = np.array([[np.cos(angle), -np.sin(angle)], [np.sin(angle), np.cos(angle)]], np.float32)
    scale = rng.uniform(0.85, 1.15)  # arm length relative to shoulder width
    shift = rng.uniform(-0.2, 0.2, size=2)  # sign made higher, lower or to the side
    # A slow wander across the clip, as if the hands' path were drawn a little differently.
    knots = rng.uniform(-0.08, 0.08, size=(3, 2))
    drift = np.stack([np.interp(np.linspace(0, 2, frames), [0, 1, 2], knots[:, axis]) for axis in range(2)], axis=1)
    for slot in range(2):
        visible = clip[:, 2 * H + slot] > 0
        hands = clip[:, slot * H:(slot + 1) * H].reshape(frames, landmarks.NUM_LANDMARKS, 3)
        wrists = hands[:, :1, :]
        hands = wrists + (hands - wrists) * rng.uniform(0.85, 1.15)  # hand size
        hands[..., 2] *= rng.uniform(0.5, 1.5) * scale  # depth is the least reliable coordinate
        own_shift = rng.uniform(-0.05, 0.05, size=2)  # each hand a little off on its own
        hands[..., :2] = hands[..., :2] @ rotation.T * scale + shift + own_shift + drift[:, None, :]
        hands += rng.normal(0, 0.02, hands.shape)  # tracking noise
        dropped = visible & (rng.random(frames) < 0.05)  # the tracker briefly losing the hand
        hands[~visible | dropped] = 0
        clip[:, slot * H:(slot + 1) * H] = hands.reshape(frames, -1)
        clip[dropped, 2 * H + slot] = 0
    return clip.astype(np.float32)


if __name__ == "__main__":
    main()
