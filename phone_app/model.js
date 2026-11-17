// The sign model in plain JavaScript: the same LSTM networks train_model.py trains,
// with weights exported by export_phone_app.py. Several networks are averaged, like
// the saved Keras model does.
//
// Keras LSTM maths: the kernel's 4 * units columns hold the input, forget, cell and
// output gates in that order; gates use the sigmoid and the cell uses tanh.

export async function loadModel(base) {
  const [info, buffer] = await Promise.all([
    fetch(`${base}/model.json`).then((r) => r.json()),
    fetch(`${base}/weights.bin`).then((r) => r.arrayBuffer()),
  ]);
  return makeModel(info, new Float32Array(buffer));
}

export function makeModel(info, weights) {
  const take = (entry) => weights.subarray(entry.offset, entry.offset + entry.shape.reduce((a, b) => a * b, 1));
  const members = info.members.map((layers) =>
    layers.map((layer) =>
      layer.type === 'lstm'
        ? {
            type: 'lstm',
            units: layer.units,
            returnSequences: layer.returnSequences,
            inputs: layer.kernel.shape[0],
            kernel: take(layer.kernel),
            recurrent: take(layer.recurrent),
            bias: take(layer.bias),
          }
        : {
            type: 'dense',
            activation: layer.activation,
            inputs: layer.kernel.shape[0],
            outputs: layer.kernel.shape[1],
            kernel: take(layer.kernel),
            bias: take(layer.bias),
          },
    ),
  );

  // clip: Float32Array of frames * featuresPerFrame numbers. Returns the averaged
  // probabilities in label order.
  function predict(clip) {
    const frames = info.sequenceFrames;
    const total = new Float64Array(info.labels.length);
    for (const layers of members) {
      let sequence = [];
      for (let t = 0; t < frames; t++) {
        sequence.push(clip.subarray(t * info.featuresPerFrame, (t + 1) * info.featuresPerFrame));
      }
      let vector = null;
      for (const layer of layers) {
        if (layer.type === 'lstm') {
          const out = lstm(layer, sequence);
          if (layer.returnSequences) sequence = out;
          else vector = out[out.length - 1];
        } else {
          vector = dense(layer, vector);
        }
      }
      for (let i = 0; i < total.length; i++) total[i] += vector[i] / members.length;
    }
    return total;
  }

  return { labels: info.labels, translations: info.translations, predict, info };
}

const sigmoid = (x) => 1 / (1 + Math.exp(-x));

function lstm(layer, sequence) {
  const { units, inputs, kernel, recurrent, bias } = layer;
  const width = 4 * units;
  let h = new Float32Array(units);
  const c = new Float32Array(units);
  const z = new Float32Array(width);
  const outputs = [];
  for (const x of sequence) {
    z.set(bias);
    for (let i = 0; i < inputs; i++) {
      const xi = x[i];
      if (xi === 0) continue; // missing hands are all zeros
      const row = i * width;
      for (let j = 0; j < width; j++) z[j] += xi * kernel[row + j];
    }
    for (let i = 0; i < units; i++) {
      const hi = h[i];
      const row = i * width;
      for (let j = 0; j < width; j++) z[j] += hi * recurrent[row + j];
    }
    const next = new Float32Array(units);
    for (let k = 0; k < units; k++) {
      const gateIn = sigmoid(z[k]);
      const gateForget = sigmoid(z[units + k]);
      const candidate = Math.tanh(z[2 * units + k]);
      const gateOut = sigmoid(z[3 * units + k]);
      c[k] = gateForget * c[k] + gateIn * candidate;
      next[k] = gateOut * Math.tanh(c[k]);
    }
    h = next;
    outputs.push(h);
  }
  return outputs;
}

function dense(layer, x) {
  const { inputs, outputs, kernel, bias, activation } = layer;
  const y = new Float32Array(outputs);
  y.set(bias);
  for (let i = 0; i < inputs; i++) {
    const xi = x[i];
    if (xi === 0) continue;
    const row = i * outputs;
    for (let j = 0; j < outputs; j++) y[j] += xi * kernel[row + j];
  }
  if (activation === 'relu') {
    for (let j = 0; j < outputs; j++) if (y[j] < 0) y[j] = 0;
  } else if (activation === 'softmax') {
    let max = -Infinity;
    for (let j = 0; j < outputs; j++) max = Math.max(max, y[j]);
    let sum = 0;
    for (let j = 0; j < outputs; j++) sum += (y[j] = Math.exp(y[j] - max));
    for (let j = 0; j < outputs; j++) y[j] /= sum;
  }
  return y;
}
