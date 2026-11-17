// Frame features and the timing rules, ported line by line from landmarks.py and
// predict_live.py, so the phone app turns movement into words exactly like the
// Python app. Change them together.

export const NUM_LANDMARKS = 21;
export const HAND_FEATURES = NUM_LANDMARKS * 3;
export const FEATURES_PER_FRAME = 2 * HAND_FEATURES + 2;
export const SEQUENCE_SECONDS = 2.0;
export const SEQUENCE_FRAMES = 30;
const MAX_GAP_SECONDS = 0.2;
export const LEFT_SHOULDER = 11, RIGHT_SHOULDER = 12, LEFT_WRIST = 15, RIGHT_WRIST = 16;

export const NOTHING = 'nothing';
const PREDICT_EVERY_SECONDS = 0.1; // predict_live.py: every 3 frames at about 30 fps
export const CONFIDENCE = 0.7;
const STABLE_SECONDS = 0.75;
const NOTHING_TO_RESET_SECONDS = 0.85;
const SAME_WORD_COOLDOWN_SECONDS = 4.0;

// MediaPipe landmarks -> array of [x, y, z] in image-height units (landmarks._to_array).
export function toArray(points, aspect) {
  return points.map((p) => [p.x * aspect, p.y, p.z * aspect]);
}

const dist2 = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);

// Put each hand in the slot whose pose wrist is nearest (landmarks._assign_hands).
export function assignHands(hands, wrists) {
  if (hands.length === 1) {
    const slots = [null, null];
    slots[dist2(hands[0][0], wrists[0]) <= dist2(hands[0][0], wrists[1]) ? 0 : 1] = hands[0];
    return slots;
  }
  if (hands.length >= 2) {
    const [a, b] = hands;
    const straight = dist2(a[0], wrists[0]) + dist2(b[0], wrists[1]);
    const swapped = dist2(a[0], wrists[1]) + dist2(b[0], wrists[0]);
    return straight <= swapped ? [a, b] : [b, a];
  }
  return [null, null];
}

// One frame -> {shoulders, hands} like landmarks.SignTracker.find, from MediaPipe results
// on a MIRRORED frame.
export function track(handLandmarks, poseLandmarks, aspect) {
  const hands = handLandmarks.map((hand) => toArray(hand, aspect));
  if (!poseLandmarks || !poseLandmarks.length) {
    return { shoulders: null, hands: [...hands, null, null].slice(0, 2) };
  }
  const body = toArray(poseLandmarks[0], aspect);
  // Frames are mirrored, so the pose model's LEFT_* landmarks land on the signer's right.
  const slots = assignHands(hands, [body[LEFT_WRIST], body[RIGHT_WRIST]]);
  return { shoulders: [body[LEFT_SHOULDER].slice(0, 2), body[RIGHT_SHOULDER].slice(0, 2)], hands: slots };
}

// landmarks.frame_features: hands relative to the shoulders' middle, in shoulder widths.
export function frameFeatures(tracked) {
  if (!tracked.shoulders) return null;
  const [s0, s1] = tracked.shoulders;
  const scale = Math.hypot(s0[0] - s1[0], s0[1] - s1[1]);
  if (scale < 1e-6) return null;
  const ox = (s0[0] + s1[0]) / 2, oy = (s0[1] + s1[1]) / 2;
  const features = new Float32Array(FEATURES_PER_FRAME);
  tracked.hands.forEach((hand, slot) => {
    if (!hand) return;
    hand.forEach(([x, y, z], i) => {
      const at = slot * HAND_FEATURES + i * 3;
      features[at] = (x - ox) / scale;
      features[at + 1] = (y - oy) / scale;
      features[at + 2] = z / scale;
    });
    features[2 * HAND_FEATURES + slot] = 1;
  });
  return features;
}

// landmarks.resample_clip: 30 evenly spaced frames over start..end, nearest frame each.
export function resampleClip(times, frames, start, end) {
  const kept = [];
  for (let i = 0; i < times.length; i++) if (frames[i]) kept.push(i);
  if (kept.length < 2) return null;
  const points = [start, ...kept.map((i) => times[i]), end];
  for (let i = 1; i < points.length; i++) if (points[i] - points[i - 1] > MAX_GAP_SECONDS) return null;
  const clip = new Float32Array(SEQUENCE_FRAMES * FEATURES_PER_FRAME);
  for (let k = 0; k < SEQUENCE_FRAMES; k++) {
    const target = start + ((end - start) * k) / (SEQUENCE_FRAMES - 1);
    let best = kept[0], bestGap = Infinity;
    for (const i of kept) {
      const gap = Math.abs(times[i] - target);
      if (gap < bestGap) (best = i), (bestGap = gap);
    }
    clip.set(frames[best], k * FEATURES_PER_FRAME);
  }
  return clip;
}

function handCoverage(clip) {
  let seen = 0;
  for (let k = 0; k < SEQUENCE_FRAMES; k++) {
    const at = k * FEATURES_PER_FRAME + 2 * HAND_FEATURES;
    if (clip[at] > 0 || clip[at + 1] > 0) seen++;
  }
  return seen / SEQUENCE_FRAMES;
}

// predict_live.Translator, with predictions timed in seconds rather than every 3 frames.
export class Translator {
  constructor(predict, labels) {
    this.predict = predict;
    this.labels = labels;
    this.times = [];
    this.frames = [];
    this.lastPrediction = -Infinity;
    this.candidate = null;
    this.candidateSince = null;
    this.lastEmitted = null;
    this.nothingSince = null;
    this.shownAt = new Map();
    this.probabilities = null;
  }

  add(t, features) {
    this.times.push(t);
    this.frames.push(features);
    while (t - this.times[0] > SEQUENCE_SECONDS + 0.5) {
      this.times.shift();
      this.frames.shift();
    }
    if (t - this.lastPrediction < PREDICT_EVERY_SECONDS - 1e-6 || t - this.times[0] < SEQUENCE_SECONDS) return null;
    this.lastPrediction = t;

    const clip = resampleClip(this.times, this.frames, t - SEQUENCE_SECONDS, t);
    if (!clip || handCoverage(clip) === 0) {
      this.probabilities = null;
      this.candidate = this.candidateSince = null;
      this.lastEmitted = this.nothingSince = null;
      return null;
    }
    this.probabilities = this.predict(clip);
    let top = 0;
    for (let i = 1; i < this.probabilities.length; i++) if (this.probabilities[i] > this.probabilities[top]) top = i;
    const label = this.labels[top];
    if (this.probabilities[top] < CONFIDENCE) {
      this.candidate = null;
      return null;
    }
    if (label !== this.candidate) {
      this.candidate = label;
      this.candidateSince = t;
    }
    if (label === NOTHING) {
      if (this.nothingSince === null) this.nothingSince = t;
      if (t - this.nothingSince >= NOTHING_TO_RESET_SECONDS) this.lastEmitted = null;
      return null;
    }
    this.nothingSince = null;
    const held = t - this.candidateSince;
    const recentlyShown = t - (this.shownAt.get(label) ?? -Infinity) < SAME_WORD_COOLDOWN_SECONDS;
    if (held >= STABLE_SECONDS && label !== this.lastEmitted && !recentlyShown) {
      this.lastEmitted = label;
      this.shownAt.set(label, t);
      return label;
    }
    return null;
  }
}
