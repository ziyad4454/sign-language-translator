enum Language { ar, en }

/// Everything the app says, in Arabic or English, including the gesture names from
/// labels_translation.json, which app.py sends when the app connects.
class AppText {
  const AppText(this.language, this.translations);

  final Language language;

  /// Gesture label -> {"en": ..., "ar": ...}; null for "nothing".
  final Map<String, Map<String, String>?> translations;

  bool get isArabic => language == Language.ar;

  String _pick(String arabic, String english) => isArabic ? arabic : english;

  /// The text shown for a gesture label.
  String word(String label) {
    if (label == 'nothing') return _pick('لا إشارة', 'No sign');
    return translations[label]?[language.name] ?? label.replaceAll('_', ' ');
  }

  String get title => _pick('مترجم لغة الإشارة', 'Sign Language Translator');
  String get clear => _pick('مسح المحادثة', 'Clear chat');
  String get undo => _pick('تراجع', 'Undo');
  String get startTest => _pick('اختبار الدقة', 'Accuracy test');
  String get stopTest => _pick('إيقاف الاختبار', 'Stop test');
  String get close => _pick('إغلاق', 'Close');
  String get cameraOff => _pick('إيقاف الكاميرا', 'Turn the camera off');
  String get cameraOn => _pick('تشغيل الكاميرا', 'Turn the camera on');
  String get soundOn => _pick('الصوت مفعّل', 'Sound on');
  String get soundMuted => _pick('الصوت مكتوم', 'Sound muted');

  /// Shown instead of [soundOn] when the words are on screen in Arabic but this
  /// computer only has an English voice to say them with.
  String get soundEnglishVoice => _pick('الصوت: إنجليزي', 'Sound on');
  String get darkMode => _pick('الوضع الداكن', 'Dark mode');
  String get lightMode => _pick('الوضع الفاتح', 'Light mode');
  String get more => _pick('المزيد', 'More');
  String get showGuesses => _pick('إظهار نسب التوقع', 'Show the guesses');
  String get hideGuesses => _pick('إخفاء نسب التوقع', 'Hide the guesses');
  String get history => _pick('السجل', 'History');
  String get emptyChat =>
      _pick('الكلمات المترجمة تظهر هنا.', 'Translated words appear here.');
  String get waitingForCamera =>
      _pick('بانتظار صورة الكاميرا…', 'Waiting for the camera…');
  String get noPredictions => _pick(
    'أعلى التوقعات تظهر هنا عند ظهور اليد.',
    'The top guesses appear here when a hand is in view.',
  );

  // The sentence line.
  String get emptySentence => _pick(
    'الكلمات تتجمع هنا لتكوين جملة.',
    'Words gather here into a sentence.',
  );
  String get speakSentence => _pick('انطق الجملة', 'Speak the sentence');
  String get newSentence => _pick('جملة جديدة', 'New sentence');

  String status(String status, String? error) => switch (status) {
    'starting' => _pick('جارٍ التشغيل…', 'Starting…'),
    'watching' => _pick('اليد ظاهرة', 'Hand in view'),
    'no_hands' => _pick('لا توجد يد', 'No hands'),
    'no_body' => _pick(
      'الرأس والكتفان غير ظاهرين',
      'Head and shoulders not in view',
    ),
    'camera_off' => _pick('الكاميرا متوقفة', 'The camera is off'),
    'error' => '${_pick('خطأ', 'Error')}: $error',
    'offline' => _pick('غير متصل بالمترجم', 'Not connected to the translator'),
    _ => status,
  };

  /// What to change about where the signer sits, or null when nothing needs changing.
  String? hint(String? hint) => switch (hint) {
    'move_closer' => _pick('الاقتراب من الكاميرا', 'Move closer to the camera'),
    'move_back' => _pick('الابتعاد قليلاً', 'Move back a little'),
    'center_yourself' => _pick(
      'الجلوس في نص الصورة',
      'Sit in the middle of the picture',
    ),
    _ => null,
  };

  // The accuracy test.
  String progress(int current, int total) =>
      _pick('الاختبار: $current من $total', 'Test: $current of $total');
  String get prompt => _pick('الإشارة المطلوبة', 'Sign this');
  String waiting(int seconds) =>
      _pick('بانتظار الإشارة… $seconds ث', 'Waiting for the sign… ${seconds}s');
  String get correct => _pick('صحيح ✓', 'Correct ✓');
  String wrong(String shown) =>
      _pick('خطأ: ظهرت «$shown»', 'Wrong: showed “$shown”');
  String get missed => _pick('لم تظهر أي كلمة', 'No word appeared');
  String get rest => _pick('استراحة، اليدان للأسفل…', 'Rest, hands down…');
  String result(int correct, int total) {
    final percent = total == 0 ? 0 : (100 * correct / total).round();
    return _pick(
      'النتيجة: $correct من $total ($percent%)',
      'Score: $correct of $total ($percent%)',
    );
  }

  String get saving => _pick('جارٍ حفظ النتيجة…', 'Saving the result…');
  String saved(String file) =>
      _pick('حُفظت النتيجة في $file', 'Result saved to $file');
  String get notSaved => _pick('تعذّر حفظ النتيجة', "Couldn't save the result");
  String get wordColumn => _pick('الكلمة', 'Word');
  String get attemptsColumn => _pick('المحاولتان', 'Attempts');
  String get noWord => _pick('لا شيء', 'nothing');
}
