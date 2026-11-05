"""Phase 1: train the gesture models on everything in data/.

Loads every CSV under data/ (your own recordings in data/ and the dictionary clips
in data/dictionary/), trains one model per kind of sample, prints how well it does
on samples it hasn't seen, and saves the models to model/.

    python train_model.py

Why these models:
- Static samples (one frame of a held hand shape) go to a random forest. With a few
  dozen samples per gesture it trains in seconds, needs no feature scaling and copes
  well with little data.
- Dynamic samples (two-second clips of 30 frames) go to a small LSTM network. It
  reads the frames in order, so it can tell signs apart by how the hands move, not
  only by where they end up.

Before the dynamic model is trained:
- Your own recordings are few next to the 120 clips per gesture made from the
  dictionary, so each is used RECORDED_COPIES times, the extra copies with small random
  changes.
- For a one-handed sign, where the free hand is shouldn't matter. In the dictionary
  videos it hangs out of view, but a webcam user's free hand often rests in view on the
  desk or lap, and the model took every such clip for "nothing": it called all 20 of
  the first recorded "hello" clips "nothing", and removing the resting hand from the
  first 10 raised "hello" from 0% to 31%. So a resting hand taken from your recordings
  is put into half of the one-handed dictionary clips, somewhere different each time,
  and removed from half of the changed copies of your one-handed recordings.

How to read the accuracy: the random 20% test split is optimistic, because clips made
from the same video or recording resemble each other. The "unseen video" checks leave
whole dictionary videos out of training and test on them, which is closer to a new
person signing; only gestures with two or more videos can be checked that way. The
"your recordings" check trains without the newer half of your own recordings of each
gesture and tests on them, which is the closest to how the translator will do for you
live.

The dynamic model doesn't use scikit-learn: on this computer Windows Smart App Control
blocks one of its compiled files (sklearn/utils/_heap), so the split and the confusion
matrix are done with numpy here. The static model still needs scikit-learn.
"""

import json
import os
import sys
from collections import Counter

import numpy as np

import landmarks

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")  # hide TensorFlow's start-up log lines

LABELS_PATH = landmarks.MODEL_DIR / "labels.json"
DYNAMIC_MODEL_PATH = landmarks.MODEL_DIR / "gesture_lstm.keras"
STATIC_MODEL_PATH = landmarks.MODEL_DIR / "gesture_static.pkl"
SOURCES_PATH = landmarks.DATA_DIR / "dictionary" / "sources.json"
NOTHING = "nothing"
TEST_SHARE = 0.2
VALIDATION_SHARE = 0.15
MIN_SAMPLES = 30
SEED = 0
RECORDED_COPIES = 3  # each of your own dynamic recordings is used this many times
ENSEMBLE_SIZE = 3  # models trained with different seeds; the saved model averages them
FREE_HAND_SHARE = 0.5  # one-handed clips that get a resting free hand added (dictionary) or removed (copies of yours)
H = landmarks.HAND_FEATURES


def main():
    data = load_data()
    if not data:
        sys.exit("No samples in data/. Run import_dictionary.py, or record with collect_data.py, first.")
    landmarks.MODEL_DIR.mkdir(exist_ok=True)
    saved = {"sequence_frames": landmarks.SEQUENCE_FRAMES, "features_per_frame": landmarks.FEATURES_PER_FRAME}
    for kind, train in (("static", train_static), ("dynamic", train_dynamic)):
        if kind not in data:
            print(f"\nNo {kind} samples, so no {kind} model.")
            continue
        X, labels, groups = data[kind]
        if check_counts(kind, labels):
            saved[f"{kind}_labels"] = train(X, labels, groups)
    LABELS_PATH.write_text(json.dumps(saved, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Saved model/labels.json")


def load_data():
    """Every sample under data/, grouped by kind: {kind: (X, labels, groups)}.

    A sample's group says where it came from: "video <id>" for a dictionary clip,
    "no hands" for an empty dictionary clip, "recorded <gesture> <row>" for one of your
    own recordings.
    """
    sources = json.loads(SOURCES_PATH.read_text(encoding="utf-8")) if SOURCES_PATH.exists() else {}
    parts = {}
    for path in sorted(landmarks.DATA_DIR.rglob("*.csv")):
        labels, samples = landmarks.load_gesture_csv(path)
        if not len(samples):
            continue
        if path.parent == SOURCES_PATH.parent:
            origins = sources.get(path.stem, [])
            groups = [origin if origin == "no hands" else f"video {origin}" for origin in origins]
            if len(groups) != len(samples):
                groups = ["dictionary"] * len(samples)
        else:
            groups = [f"recorded {path.stem} {row}" for row in range(len(samples))]
        X, y, g = parts.setdefault(landmarks.sample_kind(samples.shape[1]), ([], [], []))
        X.append(samples)
        y.extend(labels)
        g.extend(groups)
    return {kind: (np.concatenate(X), np.array(y), np.array(g)) for kind, (X, y, g) in parts.items()}


def check_counts(kind, labels):
    """Print samples per gesture and warn when there are too few or they're uneven.
    Returns False when training isn't possible."""
    counts = Counter(labels)
    print(f"\n{kind} gestures: " + ", ".join(f"{gesture} {n}" for gesture, n in sorted(counts.items())))
    if len(counts) < 2:
        print("  Need at least two gestures to train; skipped.")
        return False
    if min(counts.values()) < 5:
        print("  Need at least 5 samples of every gesture to train; skipped.")
        return False
    small = sorted(gesture for gesture, n in counts.items() if n < MIN_SAMPLES)
    if small:
        print(f"  WARNING: fewer than {MIN_SAMPLES} samples for {', '.join(small)}; the results won't be reliable.")
    if max(counts.values()) > 2 * min(counts.values()):
        print("  WARNING: uneven counts (largest more than twice the smallest); the model will lean toward the bigger gestures.")
    return True


def stratified_split(X, y, share, seed):
    """Split off `share` of every gesture's samples at random, so each gesture keeps the
    same proportion in both parts. Returns X_rest, X_split, y_rest, y_split."""
    rng = np.random.default_rng(seed)
    split = np.zeros(len(y), dtype=bool)
    for c in np.unique(y):
        members = rng.permutation(np.flatnonzero(y == c))
        split[members[:round(len(members) * share)]] = True
    return X[~split], X[split], y[~split], y[split]


def train_static(X, labels, groups):
    import joblib
    from sklearn.ensemble import RandomForestClassifier

    classes = sorted(set(labels))
    y = np.array([classes.index(label) for label in labels])
    X_train, X_test, y_train, y_test = stratified_split(X, y, TEST_SHARE, SEED)
    forest = RandomForestClassifier(n_estimators=300, random_state=SEED)
    forest.fit(X_train, y_train)
    report("static gestures, random 20% test split", y_test, forest.predict(X_test), classes)
    forest.fit(X, y)  # the saved model learns from every sample
    joblib.dump(forest, STATIC_MODEL_PATH)
    print(f"Saved model/{STATIC_MODEL_PATH.name}")
    return classes


def train_dynamic(X, labels, groups):
    classes = sorted(set(labels))
    y = np.array([classes.index(label) for label in labels])
    X = X.reshape(len(X), landmarks.SEQUENCE_FRAMES, landmarks.FEATURES_PER_FRAME).astype(np.float32)
    rng = np.random.default_rng(SEED)
    one_handed = one_handed_gestures(X, y, groups, classes)
    add_free_hands(X, y, groups, classes, one_handed, rng)
    X, y, groups = repeat_recorded(X, y, groups, one_handed, rng)

    X_train, X_test, y_train, y_test = stratified_split(X, y, TEST_SHARE, SEED)
    model = fit(X_train, y_train, len(classes))
    report("dynamic gestures, random 20% test split", y_test, predict(model, X_test), classes)
    recorded_check(X, y, groups, classes)
    unseen_checks(X, y, groups, classes)

    model = fit(X, y, len(classes))  # the saved model learns from every sample
    model.save(DYNAMIC_MODEL_PATH)
    print(f"\nSaved model/{DYNAMIC_MODEL_PATH.name}")
    return classes


def is_recorded(groups):
    return np.char.startswith(groups.astype(str), "recorded ")


def one_handed_gestures(X, y, groups, classes):
    """Class numbers of the signs made with one hand: not "nothing", and their
    dictionary clips rarely show a left hand."""
    dictionary = ~is_recorded(groups)
    left_visible = X[:, :, 2 * H + 1] > 0
    return [
        c for c, name in enumerate(classes)
        if name != NOTHING and ((y == c) & dictionary).any() and left_visible[(y == c) & dictionary].mean() < 0.2
    ]


def resting_left_hand(clip):
    """Whether a clip's left hand is in view in nearly every frame, below the chest, and
    stays in place (up to the shift a leaning body gives it)."""
    seen = clip[:, 2 * H + 1] > 0
    if seen.mean() < 0.9:
        return False
    wrists = clip[seen, H:H + 2]
    return wrists[:, 1].min() >= 0.8 and np.ptp(wrists, axis=0).max() <= 0.3


def add_free_hands(X, y, groups, classes, one_handed, rng):
    """Copy a resting left hand from your recordings into FREE_HAND_SHARE of the
    one-handed dictionary clips, somewhere different each time and drifting slightly."""
    recorded = is_recorded(groups)
    sources = [i for i in np.flatnonzero(recorded) if resting_left_hand(X[i])]
    if not sources:
        print("\nNone of your recordings has a resting left hand, so no free hand was added to dictionary clips.")
        return
    frames = landmarks.SEQUENCE_FRAMES
    targets = [i for i in np.flatnonzero(~recorded & np.isin(y, one_handed)) if rng.random() < FREE_HAND_SHARE]
    for i in targets:
        source = sources[rng.integers(len(sources))]
        hand = X[source, :, H:2 * H].reshape(frames, landmarks.NUM_LANDMARKS, 3).copy()
        place, drift = rng.uniform([-0.35, -0.5], [0.35, 0.3]), rng.uniform(-0.05, 0.05, 2)
        hand[..., :2] += (place + np.linspace(0, 1, frames)[:, None] * drift)[:, None, :]
        put = (X[source, :, 2 * H + 1] > 0) & (X[i, :, 2 * H + 1] == 0)
        X[i, put, H:2 * H] = hand[put].reshape(int(put.sum()), H)
        X[i, put, 2 * H + 1] = 1.0
    print(f"\nPut a resting left hand into {len(targets)} one-handed dictionary clips "
          f"({', '.join(classes[c] for c in one_handed)}), taken from {len(sources)} of your recordings.")


def repeat_recorded(X, y, groups, one_handed, rng):
    """Add RECORDED_COPIES - 1 changed copies of each of your recordings
    (import_dictionary.vary: tilt, size, position, hand path and tracking noise). In
    FREE_HAND_SHARE of the copies of one-handed recordings with a resting left hand, that
    hand is removed. A copy keeps its recording's group, so checks leave a recording and
    its copies out together."""
    recorded = np.flatnonzero(is_recorded(groups))
    if not len(recorded) or RECORDED_COPIES < 2:
        return X, y, groups
    from import_dictionary import vary

    index = np.repeat(recorded, RECORDED_COPIES - 1)
    copies, removed = [], 0
    for i in index:
        copy = vary(X[i], rng)
        if y[i] in one_handed and resting_left_hand(X[i]) and rng.random() < FREE_HAND_SHARE:
            copy[:, H:2 * H] = 0
            copy[:, 2 * H + 1] = 0
            removed += 1
        copies.append(copy)
    print(f"Used each of your {len(recorded)} recordings {RECORDED_COPIES} times "
          f"({len(copies)} changed copies, {removed} of them without the resting free hand).")
    return np.concatenate([X, np.stack(copies)]), np.concatenate([y, y[index]]), np.concatenate([groups, groups[index]])


def fit(X, y, num_classes):
    """Train ENSEMBLE_SIZE LSTMs with different seeds and join them into one model that
    averages their answers. On your held-out recordings three averaged models beat one:
    "nothing" 57% -> 70%, "please" 17 -> 19 of 20, the other words the same or better."""
    import keras

    members = [fit_one(X, y, num_classes, SEED + i) for i in range(ENSEMBLE_SIZE)]
    if len(members) == 1:
        return members[0]
    inputs = keras.Input(shape=(landmarks.SEQUENCE_FRAMES, landmarks.FEATURES_PER_FRAME))
    for i, member in enumerate(members):
        member.name = f"member_{i}"
    return keras.Model(inputs, keras.layers.Average()([member(inputs) for member in members]))


def fit_one(X, y, num_classes, seed):
    """Train a fresh LSTM, stopping once a validation slice of the data stops improving."""
    import keras

    keras.utils.set_random_seed(seed)
    X_fit, X_val, y_fit, y_val = stratified_split(X, y, VALIDATION_SHARE, seed)
    model = keras.Sequential(
        [
            keras.Input(shape=(landmarks.SEQUENCE_FRAMES, landmarks.FEATURES_PER_FRAME)),
            keras.layers.LSTM(64, return_sequences=True),
            keras.layers.LSTM(64),
            keras.layers.Dropout(0.3),
            keras.layers.Dense(64, activation="relu"),
            keras.layers.Dropout(0.3),
            keras.layers.Dense(num_classes, activation="softmax"),
        ]
    )
    model.compile(optimizer=keras.optimizers.Adam(1e-3), loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    stop = keras.callbacks.EarlyStopping(monitor="val_loss", patience=15, restore_best_weights=True)
    model.fit(X_fit, y_fit, validation_data=(X_val, y_val), epochs=200, batch_size=16, callbacks=[stop], verbose=0)
    return model


def predict(model, X):
    # Calling the model directly skips model.predict()'s per-model setup, which
    # printed re-tracing warnings when several models were trained in one run.
    return np.asarray(model(X, training=False)).argmax(axis=1)


def recorded_check(X, y, groups, classes):
    """Train without the newer half of your recordings of each gesture (and their
    copies), and test on those recordings: as they were recorded, and again with any
    left hand removed, as if the free hand had been out of view."""
    rows = {}
    for group in groups[is_recorded(groups)]:
        _, gesture, row = group.split(" ")
        rows.setdefault(gesture, set()).add(int(row))
    held_groups = [
        f"recorded {gesture} {row}"
        for gesture, numbers in rows.items()
        if len(numbers) >= 10
        for row in sorted(numbers)[len(numbers) // 2:]
    ]
    if not held_groups:
        return
    held = np.isin(groups, held_groups)
    _, first = np.unique(groups, return_index=True)
    original = np.zeros(len(groups), dtype=bool)
    original[first] = True  # a recording comes before its copies
    test = held & original
    without_left = X[test].copy()
    without_left[:, :, H:2 * H] = 0
    without_left[:, :, 2 * H + 1] = 0

    print("\n== your recordings: trained without the newer half of each gesture's, tested on them")
    model = fit(X[~held], y[~held], len(classes))
    for title, clips in (("as recorded", X[test]), ("left hand removed", without_left)):
        predicted = predict(model, clips)
        print(f"  {title}:")
        for c, name in enumerate(classes):
            mine = y[test] == c
            if not mine.any():
                continue
            mistakes = Counter(classes[p] for p in predicted[mine] if p != c)
            detail = f"; mistaken for {dict(mistakes)}" if mistakes else ""
            print(f"    {name}: {(predicted[mine] == c).mean():.0%} of {mine.sum()} recordings correct{detail}", flush=True)


def unseen_checks(X, y, groups, classes):
    """Leave whole dictionary videos out of training and see how their clips are classified.

    - A sign made from two or more videos: train without one video, test on its clips.
    - "nothing": train without a quarter of the other signs it is built from, and check
      those unseen signs still come out as nothing rather than as one of the words.
    """
    print("\n== unseen video checks")
    folds = []
    for c, name in enumerate(classes):
        videos = sorted({g for g, yi in zip(groups, y) if yi == c and g.startswith("video ")})
        if name == NOTHING:
            if len(videos) >= 4:
                folds.append((c, f"{len(videos[::4])} other signs never seen in training", set(videos[::4])))
        elif len(videos) >= 2:
            folds.extend((c, video, {video}) for video in videos)
    if not folds:
        print("  No gesture has two or more videos, so there is nothing to check.")
        return
    for c, description, held_videos in folds:
        held = np.isin(groups, list(held_videos))
        predicted = predict(fit(X[~held], y[~held], len(classes)), X[held])
        mistakes = Counter(classes[p] for p in predicted if p != c)
        detail = f"; mistaken for {dict(mistakes)}" if mistakes else ""
        print(f"  {classes[c]}, {description}: {(predicted == c).mean():.0%} of {held.sum()} clips correct{detail}", flush=True)


def report(title, y_true, y_pred, classes):
    y_true, y_pred = np.asarray(y_true), np.asarray(y_pred)
    print(f"\n== {title}: accuracy {(y_true == y_pred).mean():.1%} on {len(y_true)} samples")
    matrix = np.zeros((len(classes), len(classes)), dtype=int)
    np.add.at(matrix, (y_true, y_pred), 1)
    width = max(len(c) for c in classes) + 2
    print(" " * width + "".join(f"{c[:8]:>9}" for c in classes) + "   <- predicted")
    for i, name in enumerate(classes):
        print(f"{name:<{width}}" + "".join(f"{n:>9}" for n in matrix[i]))


if __name__ == "__main__":
    main()
