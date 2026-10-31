# Sign translator app (Flutter)

The translator's screen. The camera, tracking and gesture model run in `app.py` in the folder above. This app shows:

- the camera picture;
- the translated words, as a sentence and a history;
- the accuracy test.

It works in Arabic or English, and in light or dark mode.

## In the browser (the usual way)

Build it before the first run, and again after changing anything in `lib/` or `web/`:

```powershell
flutter build web --no-tree-shake-icons
```

Then start the translator from the folder above with `& $py app.py`. It serves this app at <http://127.0.0.1:8000>.

## On the Android emulator

The app on the phone still shows the computer's camera. It connects to `app.py`, which the emulator reaches at 10.0.2.2, the computer's own 127.0.0.1.

With `app.py` running and the emulator open, build and install from a temporary drive letter:

```powershell
subst T: "$env:USERPROFILE\OneDrive\سطح المكتب\ai"
cd T:\flutter_app
flutter build apk --debug --dart-define=SERVER=http://10.0.2.2:8000
flutter install -d emulator-5554 --debug
adb shell am start -n com.example.sign_translator/.MainActivity
cd $env:USERPROFILE
subst T: /D
```

- **Why the T: drive:** Gradle can't load its own files from a folder whose path has Arabic letters. `android/gradle.properties` also turns off two things for this:
  - Kotlin's incremental compilation, which breaks when the project and Flutter's package cache are on different drives;
  - the Android plugin's path check.
- **Build time:** the first build downloads Android's build tools and takes about 6 minutes. Later builds take about a minute.
- **A real phone** would need `app.py` to listen on the local network, not only on 127.0.0.1, and the build to point at the computer's address. That isn't set up yet.

## Arabic letters in the folder path

The folder name (سطح المكتب) also breaks two tools on the computer itself:

- **Building for the web:** the step that shrinks the icon font can't write its output, so `--no-tree-shake-icons` skips it.
- **Checking the code:** `flutter analyze` crashes. Use `dart analyze` instead.

## The app icon

`tool/app_icon_test.dart` draws the icon, Material's sign language symbol on the app's teal. It makes every size Android and the web need, including Android's adaptive icon, which fills the phone's icon shape.

After changing it, run `flutter test tool/app_icon_test.dart`, then rebuild.

## Files

| File | What it does |
|---|---|
| `lib/main.dart` | Starts the app; holds the language and the light or dark choice |
| `lib/home_page.dart` | The page: top bar, sentence and history |
| `lib/camera_view.dart` | The camera picture with its badges, and the guesses panel |
| `lib/sentence_card.dart` | The sentence under the camera, with its buttons |
| `lib/speaker.dart` | Says the words out loud |
| `lib/test_card.dart` | The accuracy test on screen |
| `lib/accuracy_test.dart` | The accuracy test's rules: two rounds, 10 seconds per sign, scoring |
| `lib/connection.dart` | The WebSockets to `app.py`, the camera switch, and saving test results |
| `lib/strings.dart` | Everything the app says, in Arabic and English |
| `lib/theme.dart` | Light and dark colours, and shared pieces of the page |
| `test/` | Tests for the accuracy test's rules: `flutter test` |
| `tool/app_icon_test.dart` | Draws the app icon |
