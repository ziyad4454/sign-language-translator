"""Copy the trained model and everything else the phone app needs into phone_app/.

    python export_phone_app.py

The phone app (phone_app/) runs the whole translator inside the phone's browser:
MediaPipe tracks the hands and shoulders, and the sign model runs in plain JavaScript
(phone_app/model.js). This script writes:

- phone_app/model/weights.bin: every weight of the averaged LSTM models, float32,
  little-endian, one array after another;
- phone_app/model/model.json: the layer list with each array's shape and where it
  starts in weights.bin, plus the labels and their Arabic and English text;
- phone_app/model/*.task: MediaPipe's hand and pose models, copied from model/.

Run it again after every train_model.py run.
"""

import json
import os
import re
import shutil

import numpy as np

import landmarks

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

OUT_DIR = landmarks.PROJECT_DIR / "phone_app" / "model"
TRANSLATIONS_PATH = landmarks.PROJECT_DIR / "labels_translation.json"
SIGN_GUIDE_PATH = landmarks.PROJECT_DIR / "flutter_app" / "lib" / "sign_guide.dart"


def main():
    import keras

    info = json.loads((landmarks.MODEL_DIR / "labels.json").read_text(encoding="utf-8"))
    model = keras.models.load_model(landmarks.MODEL_DIR / "gesture_lstm.keras")
    members = [layer for layer in model.layers if isinstance(layer, keras.Sequential)] or [model]

    arrays, manifest = [], []
    offset = 0

    def add(weight):
        nonlocal offset
        weight = np.ascontiguousarray(weight, dtype="<f4")
        arrays.append(weight)
        entry = {"shape": list(weight.shape), "offset": offset}
        offset += weight.size
        return entry

    for member in members:
        layers = []
        for layer in member.layers:
            kind = type(layer).__name__
            if kind == "Dropout":
                continue  # does nothing when translating
            if kind == "LSTM":
                kernel, recurrent, bias = layer.get_weights()
                layers.append({"type": "lstm", "units": layer.units, "returnSequences": layer.return_sequences,
                               "kernel": add(kernel), "recurrent": add(recurrent), "bias": add(bias)})
            elif kind == "Dense":
                kernel, bias = layer.get_weights()
                layers.append({"type": "dense", "activation": layer.activation.__name__,
                               "kernel": add(kernel), "bias": add(bias)})
            else:
                raise SystemExit(f"The phone app can't run a {kind} layer yet.")
        manifest.append(layers)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with open(OUT_DIR / "weights.bin", "wb") as file:
        for weight in arrays:
            file.write(weight.tobytes())
    translations = json.loads(TRANSLATIONS_PATH.read_text(encoding="utf-8"))
    labels = info["dynamic_labels"]
    (OUT_DIR / "model.json").write_text(json.dumps({
        "sequenceFrames": info["sequence_frames"],
        "featuresPerFrame": info["features_per_frame"],
        "labels": labels,
        "translations": {label: translations.get(label, {}) for label in labels},
        "guides": read_sign_guides(),
        "members": manifest,
    }, ensure_ascii=False), encoding="utf-8")
    for name in landmarks.MODEL_URLS:
        shutil.copyfile(landmarks.MODEL_DIR / name, OUT_DIR / name)
    print(f"Wrote {len(members)} models, {offset:,} weights, {len(labels)} labels to phone_app/model/")


def read_sign_guides():
    """Each sign's dictionary video and steps, read from the Flutter app's sign_guide.dart
    so the two apps show the same instructions."""
    source = SIGN_GUIDE_PATH.read_text(encoding="utf-8")
    guides = {}
    for match in re.finditer(r"'(\w+)': SignGuide\((.*?)\n  \),", source, re.S):
        pairs = re.findall(r"(\w+): (?:'((?:[^'\\]|\\.)*)'|(true|false))", match.group(2))
        fields = {key: text or flag for key, text, flag in pairs}
        guides[match.group(1)] = {
            "video": fields.get("video", ""),
            "ar": fields.get("arabic", "").replace("\\'", "'"),
            "en": fields.get("english", "").replace("\\'", "'"),
            "bothHands": fields.get("bothHands") == "true",
        }
    return guides


if __name__ == "__main__":
    main()
