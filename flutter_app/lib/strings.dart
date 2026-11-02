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

  // The help page.
  String get help => _pick('المساعدة', 'Help');
  String get howToUse => _pick('طريقة الاستخدام', 'How to use');
  String get signs => _pick('الإشارات', 'Signs');
  String get faq => _pick('الأسئلة الشائعة', 'FAQ');
  String get signsSource => _pick(
    'الشرح والفيديوهات من قاموس لغة الإشارة السعودية، الجمعية السعودية للإعاقة السمعية.',
    'The steps and videos come from the Saudi Sign Language dictionary, by the Saudi Association for Hearing Impairment.',
  );
  String get oneHand => _pick('باليد اليمنى', 'Right hand');
  String get bothHands => _pick('باليدين', 'Both hands');
  String get watchVideo => _pick('مشاهدة الفيديو', 'Watch the video');
  String get videoFailed => _pick(
    'تعذّر فتح الفيديو. يجب التأكد من الاتصال بالإنترنت.',
    "Couldn't open the video. Check the internet connection.",
  );

  /// Every word the model knows, in the shown language.
  List<String> get knownWords => [
    for (final MapEntry(:key, :value) in translations.entries)
      if (value != null) word(key),
  ];

  /// The steps on the help page, as (title, details).
  List<(String, String)> get steps => [
    (
      _pick('الجلوس أمام الكاميرا', 'Sit in front of the camera'),
      _pick(
        'يجب أن يظهر الرأس والكتفان والبطن في الصورة. وإذا ظهرت رسالة برتقالية على الصورة، مثل «الاقتراب من الكاميرا»، فهي توضح ما يلزم تغييره.',
        'Your head, shoulders and stomach need to be in the picture. An orange message on the picture, such as “Move closer to the camera”, says what to change.',
      ),
    ),
    (
      _pick('أداء الإشارة', 'Make the sign'),
      _pick(
        'تُؤدى الإشارة مرة واحدة بسرعة طبيعية، وتظهر الكلمة بعد لحظات. وشرح كل إشارة في تبويب «الإشارات».',
        'Make the sign once at a natural speed. The word appears a moment later. The Signs tab shows how to make each one.',
      ),
    ),
    (
      _pick('خفض اليدين', 'Lower your hands'),
      _pick(
        'بعد كل كلمة تنزل اليدان نحو ثانية، ثم تبدأ الإشارة التالية.',
        'After each word, lower your hands for about a second, then start the next sign.',
      ),
    ),
    (
      _pick('تكوين الجملة', 'Build the sentence'),
      _pick(
        'تتجمع الكلمات في السطر تحت الصورة. وبجانبه أزرار نطق الجملة، والتراجع عن آخر كلمة، وبدء جملة جديدة.',
        'Words gather in the line under the picture. The buttons next to it speak the sentence, undo the last word, and start a new sentence.',
      ),
    ),
    (
      _pick('الأزرار في الأعلى', 'The buttons at the top'),
      _pick(
        'تتحكم في الكاميرا والصوت والوضع الداكن واللغة. وفي قائمة المزيد (⋮) اختبار الدقة، وإظهار نسب التوقع، ومسح المحادثة.',
        'They control the camera, the sound, dark mode and the language. The More menu (⋮) has the accuracy test, the guesses, and clearing the chat.',
      ),
    ),
  ];

  /// The frequently asked questions, as (question, answer).
  List<(String, String)> get questions {
    final words = knownWords;
    return [
      (
        _pick(
          'ما الكلمات التي يفهمها التطبيق؟',
          'Which words does the app know?',
        ),
        words.isEmpty
            ? _pick(
                'تظهر القائمة هنا بعد الاتصال بالمترجم.',
                'The list appears here once the translator is connected.',
              )
            : _pick(
                'يفهم ${words.length} كلمة من قاموس لغة الإشارة السعودية: ${words.join('، ')}.',
                '${words.length} words from the Saudi Sign Language dictionary: ${words.join(', ')}.',
              ),
      ),
      (
        _pick('لماذا لا تظهر الكلمة؟', "Why doesn't the word appear?"),
        _pick(
          'يجب أن تكون الإشارة مثل شرحها في تبويب «الإشارات»، وأن يظهر الرأس والكتفان في الصورة مع إضاءة جيدة. والدقة تختلف من كلمة إلى أخرى. ولمعرفة ما يراه المترجم، يمكن إظهار نسب التوقع من قائمة المزيد (⋮).',
          'The sign needs to match the Signs tab, with your head and shoulders in the picture and good light. Accuracy differs from word to word. To see what the translator is seeing, show the guesses from the More menu (⋮).',
        ),
      ),
      (
        _pick('لماذا ظهرت كلمة خاطئة؟', 'Why did a wrong word appear?'),
        _pick(
          'قد يفسر المترجم حركة عادية على أنها إشارة، أو يخلط بين إشارتين متشابهتين. وزر التراجع يحذف آخر كلمة.',
          'The translator can mistake an ordinary movement for a sign, or mix up two similar signs. The undo button removes the last word.',
        ),
      ),
      (
        _pick(
          'لماذا لا تتكرر الكلمة نفسها؟',
          "Why doesn't the same word repeat?",
        ),
        _pick(
          'لمنع التكرار بالخطأ، لا تظهر الكلمة نفسها مرتين خلال 4 ثوانٍ. ولتكرارها تنزل اليدان، ثم تُعاد الإشارة بعد هذه المدة.',
          'To avoid repeating by mistake, the same word never appears twice within 4 seconds. To repeat it, lower your hands and sign again after that.',
        ),
      ),
      (
        _pick('بأي يد تُؤدى الإشارة؟', 'Which hand should I sign with?'),
        _pick(
          'باليد اليمنى كما في القاموس، وباليدين في الإشارات التي تحتاجهما، مثل «مساعدة». والإشارة باليد اليسرى قد لا تُقرأ. أما اليد غير المستخدمة فتبقى في أي وضع مريح.',
          'With the right hand, as in the dictionary, and with both hands in signs that need them, such as “Help”. Signs made with the left hand may not be read. The free hand can stay in any comfortable position.',
        ),
      ),
      (
        _pick(
          'لماذا تُنطق الكلمات بالإنجليزية؟',
          'Why are the words spoken in English?',
        ),
        _pick(
          'النطق يستخدم الأصوات المثبتة على الجهاز. وإذا لم يوجد صوت عربي تُنطق الكلمة بالإنجليزية، ويمكن إضافة صوت عربي من إعدادات الجهاز.',
          'Speech uses the voices installed on the device. Without an Arabic voice, words are spoken in English. An Arabic voice can be added in the device settings.',
        ),
      ),
      (
        _pick('هل يترجم جملاً كاملة؟', 'Does it translate whole sentences?'),
        _pick(
          'يترجم كلمة كلمة، وتتكوّن الجملة من الكلمات بترتيبها، ولا يعدّل قواعدها.',
          'It translates one word at a time. The sentence keeps the words in order, and the app doesn’t change their grammar.',
        ),
      ),
      (
        _pick(
          'هل يُغني عن المترجم البشري؟',
          'Can it replace a human interpreter?',
        ),
        _pick(
          'لا. هذا مشروع تجريبي وقد يخطئ، فلا يُعتمد عليه في المواقف الطبية أو الطارئة.',
          "No. It's an experimental project and it can make mistakes, so don't rely on it in medical situations or emergencies.",
        ),
      ),
      (
        _pick('هل تُحفظ صورتي؟', 'Is my picture saved?'),
        _pick(
          'لا تُحفظ الصورة ولا تُرسل إلى الإنترنت، فالكاميرا والترجمة تعملان على هذا الكمبيوتر. ويُحفظ فيه سجل بالكلمات ونسب التوقع، بدون صور. وزر الكاميرا يوقفها تماماً.',
          "Your picture isn't saved or sent to the internet: the camera and the translation run on this computer. A log of the words and guesses is saved there, with no pictures. The camera button turns the camera off completely.",
        ),
      ),
      (
        _pick('هل تُحفظ المحادثة؟', 'Is the chat saved?'),
        _pick(
          'لا. تختفي الكلمات عند إغلاق التطبيق أو إعادة تحميله.',
          'No. The words are gone when the app is closed or reloaded.',
        ),
      ),
      (
        _pick('ما اختبار الدقة؟', 'What is the accuracy test?'),
        _pick(
          'يطلب التطبيق كل إشارة مرتين، مع 10 ثوانٍ لكل إشارة، ثم يعرض النتيجة. وهو يقيس دقة المترجم، لا مهارة المستخدم.',
          'The app asks for each sign twice, with 10 seconds for each, then shows the score. It measures the translator, not you.',
        ),
      ),
      (
        _pick(
          'ما معنى «غير متصل بالمترجم»؟',
          'What does “Not connected to the translator” mean?',
        ),
        _pick(
          'التطبيق لا يصل إلى برنامج المترجم على الكمبيوتر. يجب التأكد من تشغيله، وبعدها يعود الاتصال تلقائياً.',
          "The app can't reach the translator program on the computer. Make sure it's running, and the app will reconnect by itself.",
        ),
      ),
    ];
  }

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
