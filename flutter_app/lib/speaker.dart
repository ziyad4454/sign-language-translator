import 'package:flutter_tts/flutter_tts.dart';

/// Says the translated words out loud. It uses the voices installed on the computer,
/// and this one has only English ones, so a word is said in Arabic when an Arabic
/// voice exists and in English otherwise. Muting is the sound button in the top bar.
class Speaker {
  final FlutterTts _tts = FlutterTts();
  bool muted = false;
  bool _arabicVoice = false;

  Future<void> say({
    required String arabic,
    required String english,
    required bool preferArabic,
  }) async {
    if (muted) return;
    final useArabic = preferArabic && await hasArabicVoice();
    final text = useArabic ? arabic : english;
    if (text.isEmpty) return;
    try {
      await _tts.setLanguage(useArabic ? 'ar-SA' : 'en-US');
      await _tts.speak(text);
    } catch (_) {
      // No voice at all here: the words are still on the screen.
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Nothing was being said.
    }
  }

  /// Whether the computer has an Arabic voice. Checked again until one turns up, since
  /// the browser can report its voices a moment after the page opens.
  Future<bool> hasArabicVoice() async {
    if (_arabicVoice) return true;
    try {
      _arabicVoice = await _tts.isLanguageAvailable('ar-SA') == true;
    } catch (_) {
      _arabicVoice = false;
    }
    return _arabicVoice;
  }
}
