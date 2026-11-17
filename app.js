// The phone app: camera -> MediaPipe -> features -> sign model -> timing rules -> words.
// Everything runs on the phone; nothing is sent anywhere.
//
// Test mode: index.html?video=<file> translates a video file instead of the camera and
// puts the words found in window.translatedWords (used to compare with predict_live.py).

import { FilesetResolver, HandLandmarker, PoseLandmarker } from './mediapipe/vision_bundle.mjs';
import { loadModel } from './model.js';
import { Translator, track, frameFeatures, NOTHING, CONFIDENCE } from './translator.js';

const TEXT = {
  ar: {
    dir: 'rtl', title: 'مترجم لغة الإشارة', other: 'EN', help: 'المساعدة',
    startText: 'ترجمة لغة الإشارة السعودية إلى كلام مكتوب ومسموع. كل شيء يعمل داخل جوالك.',
    start: 'ابدأ', loading: 'جارٍ التحميل…', loadingDone: '', cameraError: 'تعذّر فتح الكاميرا. اسمح للمتصفح باستخدامها ثم أعد المحاولة.',
    loadError: 'تعذّر تحميل المترجم. تأكد من الاتصال بالإنترنت أول مرة ثم أعد المحاولة.',
    noBody: 'أظهر رأسك وكتفيك', noHands: 'لا توجد يد', handsIn: 'اليد ظاهرة',
    closer: 'اقترب من الكاميرا', back: 'ابتعد قليلاً', center: 'توسّط الصورة',
    placeholder: 'الكلمات تتجمع هنا لتكوين جملة.', history: 'السجل', historyEmpty: 'الكلمات المترجمة تظهر هنا.',
    helpTitle: 'طريقة الاستخدام',
    steps: [
      'ثبّت الجوال أمامك، بحيث يظهر رأسك وكتفاك وبطنك في الصورة.',
      'اضغط «ابدأ» واسمح باستخدام الكاميرا.',
      'أدِّ الإشارة مرة واحدة بسرعة طبيعية، ثم أنزل يديك.',
      'تظهر الكلمة في الجملة وتُنطق. زر الرجوع يحذف آخر كلمة.',
      'لإضافة التطبيق إلى الشاشة الرئيسية: زر المشاركة في Safari ثم «إضافة إلى الشاشة الرئيسية».',
    ],
    signsTitle: 'الإشارات', signsNote: 'من القاموس الرسمي للغة الإشارة السعودية (الجمعية السعودية للإعاقة السمعية).',
    oneHand: 'باليد اليمنى', bothHands: 'باليدين', video: 'مشاهدة الفيديو',
  },
  en: {
    dir: 'ltr', title: 'Sign Translator', other: 'عربي', help: 'Help',
    startText: 'Turns Saudi Sign Language into written and spoken words. Everything runs on your phone.',
    start: 'Start', loading: 'Loading…', loadingDone: '', cameraError: 'Could not open the camera. Allow the browser to use it, then try again.',
    loadError: 'Could not load the translator. Connect to the internet the first time, then try again.',
    noBody: 'Show your head and shoulders', noHands: 'No hands', handsIn: 'Hand in view',
    closer: 'Move closer', back: 'Move back a little', center: 'Move to the middle',
    placeholder: 'Words collect here into a sentence.', history: 'History', historyEmpty: 'Translated words appear here.',
    helpTitle: 'How to use',
    steps: [
      'Stand the phone in front of you so your head, shoulders and stomach are in the picture.',
      'Tap Start and allow the camera.',
      'Make the sign once at a normal pace, then lower your hands.',
      'The word is added to the sentence and spoken. The undo button removes the last word.',
      'To add the app to the Home Screen: Safari’s Share button, then “Add to Home Screen”.',
    ],
    signsTitle: 'Signs', signsNote: 'From the official Saudi Sign Language dictionary (Saudi Association for Hearing Impairment).',
    oneHand: 'right hand', bothHands: 'both hands', video: 'Watch the video',
  },
};

const ICONS = {
  sound: 'M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z',
  mute: 'M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z',
  flip: 'M20 5h-3.17L15 3H9L7.17 5H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm-5 11.5V14H9v2.5L5.5 13 9 9.5V12h6V9.5l3.5 3.5-3.5 3.5z',
  speak: 'M9 13c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4zm7.76-9.64l-1.68 1.69c.84 1.18.84 2.71 0 3.89l1.68 1.69c2.02-2.02 2.02-5.07 0-7.27zM20.07 2l-1.63 1.63c2.77 3.02 2.77 7.56 0 10.74L20.07 16c3.9-3.89 3.91-9.95 0-14z',
  undo: 'M12.5 8c-2.65 0-5.05.99-6.9 2.6L2 7v9h9l-3.62-3.62c1.39-1.16 3.16-1.88 5.12-1.88 3.54 0 6.55 2.31 7.6 5.5l2.37-.78C21.08 11.03 17.15 8 12.5 8z',
  clear: 'M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z',
  help: 'M11 18h2v-2h-2v2zm1-16C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm0-14c-2.21 0-4 1.79-4 4h2c0-1.1.9-2 2-2s2 .9 2 2c0 2-3 1.75-3 5h2c0-2.25 3-2.5 3-5 0-2.21-1.79-4-4-4z',
  close: 'M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
};
const svg = (d) => `<svg width="24" height="24" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="${d}"/></svg>`;

const FAR_SHOULDERS = 0.3, CLOSE_SHOULDERS = 0.75, SIDE_MARGIN = 0.25; // app.py's seat hints
const MAX_SIDE = 1280; // frames are scaled down to this, like the 1280 x 720 webcam
const VIDEO_TAIL_SECONDS = 1.0;

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const testVideo = params.get('video');
const state = {
  lang: localStorageGet('lang') || 'ar',
  sound: localStorageGet('sound') !== 'off',
  facing: 'user',
  words: [],
  running: false,
};
let model, hands, pose, translator, stream;
const work = document.createElement('canvas');
const workCtx = work.getContext('2d', { willReadFrequently: false });
const view = $('view');
const viewCtx = view.getContext('2d');
window.translatedWords = [];
window.trace = []; // test mode: [seconds, hands, body found, top guess] per frame

function localStorageGet(key) { try { return localStorage.getItem(key); } catch { return null; } }
function localStorageSet(key, value) { try { localStorage.setItem(key, value); } catch { /* private mode */ } }
const t = () => TEXT[state.lang];

// ---------- text and layout ----------

function render() {
  const text = t();
  document.documentElement.lang = state.lang;
  document.documentElement.dir = text.dir;
  document.title = text.title;
  $('title').textContent = text.title;
  $('lang').textContent = text.other;
  $('help').innerHTML = svg(ICONS.help);
  $('help').setAttribute('aria-label', text.help);
  $('startText').textContent = text.startText;
  $('startButton').textContent = text.start;
  $('historyTitle').textContent = text.history;
  $('historyEmpty').textContent = text.historyEmpty;
  $('sound').innerHTML = svg(state.sound ? ICONS.sound : ICONS.mute);
  $('flip').innerHTML = svg(ICONS.flip);
  $('speak').innerHTML = svg(ICONS.speak);
  $('undo').innerHTML = svg(ICONS.undo);
  $('clear').innerHTML = svg(ICONS.clear);
  $('helpClose').innerHTML = svg(ICONS.close);
  renderSentence();
  renderHistory();
  if (model) renderHelp();
}

const wordText = (label) => (model?.translations[label] || {})[state.lang] || label.replaceAll('_', ' ');

function renderSentence() {
  const sentence = $('sentence');
  sentence.classList.toggle('placeholder', !state.words.length);
  sentence.textContent = state.words.length ? state.words.map((w) => wordText(w.label)).join(' ') : t().placeholder;
}

function renderHistory() {
  const list = $('history');
  list.replaceChildren();
  for (const w of [...state.words].reverse()) {
    const item = document.createElement('li');
    const name = document.createElement('b');
    name.textContent = wordText(w.label);
    const detail = document.createElement('small');
    detail.textContent = `${Math.round(w.confidence * 100)}% · ${w.time}`;
    item.append(name, detail);
    list.append(item);
  }
  $('historyEmpty').hidden = state.words.length > 0;
}

function renderHelp() {
  const text = t();
  $('helpTitle').textContent = text.helpTitle;
  $('steps').replaceChildren(...text.steps.map((s) => Object.assign(document.createElement('li'), { textContent: s })));
  $('signsTitle').textContent = `${text.signsTitle} (${model.labels.length - 1})`;
  $('signsNote').textContent = text.signsNote;
  const signs = model.labels.filter((l) => l !== NOTHING && model.guides[l]);
  $('signs').replaceChildren(...signs.map((label) => {
    const guide = model.guides[label];
    const box = document.createElement('details');
    const summary = document.createElement('summary');
    summary.textContent = wordText(label);
    const hands = document.createElement('small');
    hands.textContent = guide.bothHands ? text.bothHands : text.oneHand;
    summary.append(hands);
    const steps = document.createElement('p');
    steps.textContent = guide[state.lang];
    const link = Object.assign(document.createElement('a'), {
      href: `https://sshi.sa/category/${guide.video}`, target: '_blank', rel: 'noopener', textContent: text.video,
    });
    box.append(summary, steps, link);
    return box;
  }));
}

// ---------- speech ----------

function voiceFor(lang) {
  const voices = speechSynthesis.getVoices();
  return voices.find((v) => v.lang.toLowerCase().startsWith(lang)) || null;
}

// Says the given labels in the screen's language. With no Arabic voice on the device it
// says the English words instead, like the Flutter app.
function say(labels) {
  if (!('speechSynthesis' in window) || !labels.length) return;
  let lang = state.lang;
  let voice = voiceFor(lang);
  if (lang === 'ar' && !voice) {
    lang = 'en';
    voice = voiceFor('en');
  }
  const line = labels.map((label) => (model.translations[label] || {})[lang] || label.replaceAll('_', ' ')).join(' ');
  const utterance = new SpeechSynthesisUtterance(line);
  utterance.lang = lang === 'ar' ? 'ar-SA' : 'en-US';
  if (voice) utterance.voice = voice;
  speechSynthesis.cancel();
  speechSynthesis.speak(utterance);
}

// ---------- loading ----------

async function load() {
  $('loading').textContent = t().loading;
  $('startButton').disabled = true;
  try {
    const fileset = await FilesetResolver.forVisionTasks(new URL('mediapipe/wasm', location.href).href);
    const [loaded, handModel, poseModel] = await Promise.all([
      loadModel('model'),
      HandLandmarker.createFromOptions(fileset, {
        baseOptions: { modelAssetPath: 'model/hand_landmarker.task', delegate: 'CPU' },
        runningMode: 'VIDEO', numHands: 2, minHandDetectionConfidence: 0.6,
      }),
      PoseLandmarker.createFromOptions(fileset, {
        baseOptions: { modelAssetPath: 'model/pose_landmarker_lite.task', delegate: 'CPU' },
        runningMode: 'VIDEO', minPoseDetectionConfidence: 0.6,
      }),
    ]);
    model = loaded;
    model.guides = model.info.guides || {};
    hands = handModel;
    pose = poseModel;
    $('loading').textContent = t().loadingDone;
    $('startButton').disabled = false;
    renderHelp();
    if (testVideo) start();
  } catch (error) {
    console.error(error);
    $('loading').textContent = t().loadError;
  }
}

// ---------- camera and the frame loop ----------

async function openCamera() {
  stream?.getTracks().forEach((track) => track.stop());
  stream = await navigator.mediaDevices.getUserMedia({
    audio: false,
    video: { facingMode: state.facing, width: { ideal: 1280 }, height: { ideal: 720 } },
  });
  const video = $('video');
  video.srcObject = stream;
  await video.play();
}

async function start() {
  if (state.running) return;
  // A first, silent utterance inside the tap lets iOS speak later words.
  if ('speechSynthesis' in window && !testVideo) {
    const unlock = new SpeechSynthesisUtterance(' ');
    unlock.volume = 0;
    speechSynthesis.speak(unlock);
  }
  $('start').hidden = true;
  translator = new Translator(model.predict, model.labels);
  state.lastTimestamp = -1;
  if (testVideo) {
    runTestVideo().catch(console.error);
    return;
  }
  try {
    await openCamera();
  } catch (error) {
    console.error(error);
    $('start').hidden = false;
    $('loading').textContent = t().cameraError;
    return;
  }
  state.running = true;
  requestAnimationFrame(loop);
}

function loop() {
  if (!state.running) return;
  const video = $('video');
  if (video.readyState >= 2 && video.videoWidth) step(video, performance.now() / 1000);
  requestAnimationFrame(loop);
}

// Test mode: every frame of the video in turn, then the last frame held for a second
// (a live signer keeps standing there), like predict_live.frames_from_video.
async function runTestVideo() {
  const video = $('video');
  const fps = Number(params.get('fps')) || 25;
  const frameCount = Number(params.get('frames'));
  if (frameCount) {
    // testVideo is a folder of numbered JPEG frames (0000.jpg, 0001.jpg, ...).
    let image;
    for (let i = 0; i < frameCount; i++) {
      image = new Image();
      image.src = `${testVideo}/${String(i).padStart(4, '0')}.jpg`;
      await image.decode();
      step(image, i / fps);
    }
    for (let i = 0; i < VIDEO_TAIL_SECONDS * fps; i++) step(image, (frameCount + i) / fps);
    window.testDone = true;
    return;
  }
  video.src = testVideo;
  video.muted = true;
  await new Promise((resolve) => video.addEventListener('loadeddata', resolve, { once: true }));
  const frames = Math.floor(video.duration * fps);
  for (let i = 0; i < frames; i++) {
    // A seek only counts once the new frame has been presented; reading the video right
    // after 'seeked' can still give the previous picture.
    const presented = new Promise((resolve) => {
      if (video.requestVideoFrameCallback) video.requestVideoFrameCallback(() => resolve());
      else video.addEventListener('seeked', resolve, { once: true });
      setTimeout(resolve, 1000);
    });
    video.currentTime = (i + 0.5) / fps;
    await presented;
    step(video, i / fps);
  }
  for (let i = 0; i < VIDEO_TAIL_SECONDS * fps; i++) step(video, (frames + i) / fps);
  window.testDone = true;
}

function step(video, seconds) {
  const sourceWidth = video.videoWidth || video.naturalWidth, sourceHeight = video.videoHeight || video.naturalHeight;
  const scale = Math.min(1, MAX_SIDE / Math.max(sourceWidth, sourceHeight));
  const width = Math.round(sourceWidth * scale), height = Math.round(sourceHeight * scale);
  if (work.width !== width || work.height !== height) {
    work.width = view.width = width;
    work.height = view.height = height;
    document.querySelector('.camera').style.aspectRatio = `${width} / ${height}`;
  }
  // Mirrored, like landmarks.read_mirrored_frame: the models were trained on mirrored frames.
  workCtx.setTransform(-1, 0, 0, 1, width, 0);
  workCtx.drawImage(video, 0, 0, width, height);
  workCtx.setTransform(1, 0, 0, 1, 0, 0);

  const ms = Math.max(Math.round(seconds * 1000), state.lastTimestamp + 1);
  state.lastTimestamp = ms;
  const handResult = hands.detectForVideo(work, ms);
  const poseResult = pose.detectForVideo(work, ms);
  const aspect = width / height;
  const tracked = track(handResult.landmarks || [], poseResult.landmarks || [], aspect);
  const word = translator.add(seconds, frameFeatures(tracked));
  if (testVideo) {
    const p = translator.probabilities;
    const top = p ? p.indexOf(Math.max(...p)) : -1;
    const wrist = poseResult.landmarks?.[0]?.[15];
    window.trace.push([+seconds.toFixed(2), tracked.hands.filter(Boolean).length, !!tracked.shoulders,
      top >= 0 ? `${model.labels[top]} ${p[top].toFixed(2)}` : '', wrist ? +wrist.y.toFixed(3) : null]);
  }

  draw(tracked, width, height);
  showStatus(tracked, aspect);
  if (word) addWord(word, translator.probabilities[model.labels.indexOf(word)]);
}

function draw(tracked, width, height) {
  const mirrored = state.facing === 'user' || testVideo;
  if (mirrored) {
    viewCtx.drawImage(work, 0, 0);
  } else {
    viewCtx.drawImage($('video'), 0, 0, width, height);
  }
  // Tracked points are in mirrored-image height units; the back camera is shown unmirrored.
  const px = ([x, y]) => [mirrored ? x * height : width - x * height, y * height];
  viewCtx.lineWidth = Math.max(2, width / 320);
  if (tracked.shoulders) {
    viewCtx.strokeStyle = 'rgba(220,220,220,.9)';
    viewCtx.beginPath();
    viewCtx.moveTo(...px(tracked.shoulders[0]));
    viewCtx.lineTo(...px(tracked.shoulders[1]));
    viewCtx.stroke();
  }
  const colors = ['#00BEFF', '#FF8C00'];
  tracked.hands.forEach((hand, slot) => {
    if (!hand) return;
    viewCtx.strokeStyle = colors[slot];
    viewCtx.beginPath();
    for (const { start, end } of HandLandmarker.HAND_CONNECTIONS) {
      viewCtx.moveTo(...px(hand[start]));
      viewCtx.lineTo(...px(hand[end]));
    }
    viewCtx.stroke();
    viewCtx.fillStyle = '#fff';
    for (const point of hand) {
      const [x, y] = px(point);
      viewCtx.beginPath();
      viewCtx.arc(x, y, viewCtx.lineWidth * 1.3, 0, 2 * Math.PI);
      viewCtx.fill();
    }
  });
}

function showStatus(tracked, aspect) {
  const text = t();
  const handCount = tracked.hands.filter(Boolean).length;
  $('status').textContent = !tracked.shoulders ? text.noBody : handCount ? text.handsIn : text.noHands;
  let hint = null;
  if (tracked.shoulders) {
    const [a, b] = tracked.shoulders;
    const width = Math.hypot(a[0] - b[0], a[1] - b[1]) / Math.min(1, aspect);
    const middle = (a[0] + b[0]) / 2;
    if (width < FAR_SHOULDERS) hint = text.closer;
    else if (width > CLOSE_SHOULDERS) hint = text.back;
    else if (middle < SIDE_MARGIN * aspect || middle > (1 - SIDE_MARGIN) * aspect) hint = text.center;
  }
  $('hint').hidden = !hint;
  $('hint').textContent = hint || '';
  const guess = $('guess');
  const p = translator.probabilities;
  if (p && handCount) {
    let top = 0;
    for (let i = 1; i < p.length; i++) if (p[i] > p[top]) top = i;
    const label = model.labels[top];
    guess.hidden = label === NOTHING || p[top] < 0.5;
    guess.textContent = `${wordText(label)}  ${Math.round(p[top] * 100)}%`;
    guess.style.outline = p[top] >= CONFIDENCE ? '2px solid #2DD4BF' : 'none';
  } else {
    guess.hidden = true;
  }
}

function addWord(label, confidence) {
  const now = new Date();
  state.words.push({ label, confidence, time: now.toLocaleTimeString(state.lang === 'ar' ? 'ar-SA' : 'en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' }) });
  window.translatedWords.push(label);
  renderSentence();
  renderHistory();
  if (state.sound && !testVideo) say([label]);
}

// ---------- buttons ----------

$('startButton').addEventListener('click', start);
$('lang').addEventListener('click', () => {
  state.lang = state.lang === 'ar' ? 'en' : 'ar';
  localStorageSet('lang', state.lang);
  render();
});
$('sound').addEventListener('click', () => {
  state.sound = !state.sound;
  localStorageSet('sound', state.sound ? 'on' : 'off');
  if (!state.sound) speechSynthesis?.cancel();
  render();
});
$('flip').addEventListener('click', async () => {
  state.facing = state.facing === 'user' ? 'environment' : 'user';
  if (state.running && !testVideo) {
    try { await openCamera(); } catch (error) { console.error(error); }
  }
});
$('speak').addEventListener('click', () => say(state.words.map((w) => w.label)));
$('undo').addEventListener('click', () => { state.words.pop(); renderSentence(); renderHistory(); });
$('clear').addEventListener('click', () => { state.words = []; renderSentence(); renderHistory(); });
$('help').addEventListener('click', () => $('helpDialog').showModal());
$('helpClose').addEventListener('click', () => $('helpDialog').close());
document.addEventListener('visibilitychange', () => {
  // iOS stops the camera in the background; reopen it when the app comes back.
  if (!document.hidden && state.running && !testVideo && !stream?.active) openCamera().catch(console.error);
});
if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('sw.js').catch(console.error);
}

render();
load();
