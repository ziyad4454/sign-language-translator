# Phone app

The whole translator running inside a phone's browser, on the phone's own camera: no laptop, no server, and nothing is sent anywhere.

- **Open it:** <https://ziyad4454.github.io/sign-language-translator/> in Safari (iPhone) or Chrome (Android).
- **Install it:** Safari's Share button, then **Add to Home Screen**. It then opens full screen from its own icon, and works offline after the first visit.
- **How it works:** MediaPipe (web version 1.0.1, in `mediapipe/`) tracks the hands and shoulders, `translator.js` turns them into the same features and timing rules as `landmarks.py` and `predict_live.py`, and `model.js` runs the same averaged LSTM models in plain JavaScript.
- **Checked against the Python app:** the JavaScript model gives the same probabilities as Keras to within 0.0000002 on 20 recorded clips, and the whole pipeline found the right word, with no wrong words, in 15 of 15 dictionary videos.

## Updating it

After retraining, copy the new model in, then publish:

```powershell
& $py export_phone_app.py
```

Then change `VERSION` in `sw.js`, so phones that installed the app fetch the new files.

## Testing without a camera

`index.html?video=<folder>&frames=<n>` translates numbered JPEG frames (`0000.jpg`, `0001.jpg`, …) instead of the camera, and puts the words found in `window.translatedWords`.
