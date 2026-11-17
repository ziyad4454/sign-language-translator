// Keeps the app working offline after the first visit: every file the app loads is
// stored on the phone and served from there. Change VERSION after updating the app so
// phones fetch the new files.
const VERSION = 'sign-translator-v1';
const CORE = [
  './', 'index.html', 'style.css', 'app.js', 'model.js', 'translator.js', 'manifest.webmanifest',
  'icons/apple-touch-icon.png', 'icons/Icon-192.png', 'icons/Icon-512.png',
  'mediapipe/vision_bundle.mjs', 'mediapipe/wasm/vision_wasm_internal.js', 'mediapipe/wasm/vision_wasm_internal.wasm',
  'model/model.json', 'model/weights.bin', 'model/hand_landmarker.task', 'model/pose_landmarker_lite.task',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(VERSION).then((cache) => cache.addAll(CORE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== VERSION).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== location.origin) return;
  event.respondWith(
    caches.match(event.request, { ignoreSearch: true }).then((hit) => hit || fetch(event.request).then((response) => {
      if (response.ok) {
        const copy = response.clone();
        caches.open(VERSION).then((cache) => cache.put(event.request, copy));
      }
      return response;
    })),
  );
});
