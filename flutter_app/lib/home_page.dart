import 'dart:async';

import 'package:flutter/material.dart';

import 'accuracy_test.dart';
import 'camera_view.dart';
import 'connection.dart';
import 'help_page.dart';
import 'sentence_card.dart';
import 'speaker.dart';
import 'strings.dart';
import 'test_card.dart';
import 'theme.dart';

/// Below this width the camera and the history are stacked instead of side by side.
const wideLayoutWidth = 900.0;

enum _MenuItem { test, guesses, clear }

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.connection,
    required this.language,
    required this.onLanguage,
    required this.onToggleTheme,
  });

  final EngineConnection connection;
  final Language language;
  final ValueChanged<Language> onLanguage;

  /// Switches between light and dark, given the brightness now on screen.
  final ValueChanged<Brightness> onToggleTheme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _words = <Word>[];
  final _historyScroll = ScrollController();
  final _speaker = Speaker();
  late final StreamSubscription<Word> _wordSubscription;
  AccuracyTest? _test;
  int _sentenceStart = 0; // the sentence card holds the words from here on
  bool _arabicVoice = false; // whether this device can say the words in Arabic
  bool _showGuesses = false; // the panel with the model's three top guesses

  EngineConnection get _connection => widget.connection;

  AppText get _text => AppText(widget.language, _connection.translations.value);

  List<Word> get _sentence => _words.sublist(_sentenceStart);

  @override
  void initState() {
    super.initState();
    _connection.translations.addListener(_refresh);
    _connection.testOrder.addListener(_refresh);
    _wordSubscription = _connection.words.listen(_addWord);
    _connection.start();
    _speaker.hasArabicVoice().then((available) {
      if (mounted) setState(() => _arabicVoice = available);
    });
  }

  @override
  void dispose() {
    _wordSubscription.cancel();
    _connection.translations.removeListener(_refresh);
    _connection.testOrder.removeListener(_refresh);
    _test
      ?..stop()
      ..dispose();
    _speaker.stop();
    _connection.close();
    _historyScroll.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  /// Says something out loud, in the shown language when a voice for it exists.
  /// [pick] builds the same text from the Arabic and the English names.
  void _speak(String Function(AppText text) pick) {
    final translations = _connection.translations.value;
    _speaker.say(
      arabic: pick(AppText(Language.ar, translations)),
      english: pick(AppText(Language.en, translations)),
      preferArabic: widget.language == Language.ar,
    );
  }

  void _addWord(Word word) {
    setState(() => _words.add(word));
    _test?.answer(word.label);
    _speak((text) => text.word(word.label));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_historyScroll.hasClients) {
        _historyScroll.animateTo(
          _historyScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _undo() {
    if (_words.isEmpty) return;
    setState(() {
      _words.removeLast();
      _sentenceStart = _sentenceStart.clamp(0, _words.length);
    });
  }

  void _clearHistory() {
    setState(() {
      _words.clear();
      _sentenceStart = 0;
    });
  }

  void _speakSentence() {
    _speak((text) => _sentence.map((word) => text.word(word.label)).join(' '));
  }

  void _toggleSound() {
    setState(() => _speaker.muted = !_speaker.muted);
    if (_speaker.muted) _speaker.stop();
  }

  Future<void> _toggleCamera(bool on) async {
    try {
      await _connection.setCamera(on);
    } catch (_) {
      // app.py didn't answer; the status badge shows when it's gone.
    }
  }

  void _startTest() {
    setState(() {
      _test = AccuracyTest(
        _connection.testOrder.value,
        save: (trials) => _connection.saveTestResults([
          for (final trial in trials) trial.toJson(),
        ]),
      );
    });
  }

  void _closeTest() {
    final test = _test!..stop();
    setState(() => _test = null);
    // Only once the card is gone: it listens to the test until then.
    WidgetsBinding.instance.addPostFrameCallback((_) => test.dispose());
  }

  void _openHelp() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => HelpPage(text: _text)));
  }

  void _onMenu(_MenuItem item) {
    switch (item) {
      case _MenuItem.test:
        _startTest();
      case _MenuItem.guesses:
        setState(() => _showGuesses = !_showGuesses);
      case _MenuItem.clear:
        _clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final colors = AppColors.of(context);
    return Title(
      title: text.title,
      color: Palette.accent,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _topBar(text, colors),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      constraints.maxWidth >= wideLayoutWidth
                      ? _wideLayout(text, colors)
                      : _narrowLayout(text, colors),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(AppText text, AppColors colors) {
    final brightness = Theme.of(context).brightness;
    final canTest = _connection.testOrder.value.isNotEmpty && _test == null;
    final soundLabel = _speaker.muted
        ? text.soundMuted
        : text.isArabic && !_arabicVoice
        ? text.soundEnglishVoice
        : text.soundOn;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 8, 6),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 2,
        children: [
          Text(
            text.title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ValueListenableBuilder(
                valueListenable: _connection.state,
                builder: (context, state, _) => IconButton(
                  tooltip: state.camera ? text.cameraOff : text.cameraOn,
                  onPressed: () => _toggleCamera(!state.camera),
                  icon: Icon(
                    state.camera ? Icons.videocam : Icons.videocam_off,
                  ),
                ),
              ),
              IconButton(
                tooltip: soundLabel,
                onPressed: _toggleSound,
                icon: Icon(_speaker.muted ? Icons.volume_off : Icons.volume_up),
              ),
              IconButton(
                tooltip: brightness == Brightness.dark
                    ? text.lightMode
                    : text.darkMode,
                onPressed: () => widget.onToggleTheme(brightness),
                icon: Icon(
                  brightness == Brightness.dark
                      ? Icons.light_mode
                      : Icons.dark_mode,
                ),
              ),
              const SizedBox(width: 4),
              // Each label is written in its own language, so it reads the same
              // whichever language the app is showing.
              SegmentedButton<Language>(
                segments: const [
                  ButtonSegment(value: Language.ar, label: Text('عربي')),
                  ButtonSegment(value: Language.en, label: Text('English')),
                ],
                selected: {widget.language},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onSelectionChanged: (choice) => widget.onLanguage(choice.first),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _openHelp,
                style: TextButton.styleFrom(foregroundColor: colors.ink),
                icon: const Icon(Icons.help_outline),
                label: Text(text.help),
              ),
              PopupMenuButton<_MenuItem>(
                tooltip: text.more,
                icon: const Icon(Icons.more_vert),
                onSelected: _onMenu,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _MenuItem.test,
                    enabled: canTest,
                    child: ListTile(
                      leading: const Icon(Icons.fact_check_outlined),
                      title: Text(text.startTest),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MenuItem.guesses,
                    child: ListTile(
                      leading: const Icon(Icons.insights),
                      title: Text(
                        _showGuesses ? text.hideGuesses : text.showGuesses,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MenuItem.clear,
                    enabled: _words.isNotEmpty,
                    child: ListTile(
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: Text(text.clear),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wideLayout(AppText text, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _mainColumn(text),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: _history(text, colors)),
        ],
      ),
    );
  }

  Widget _narrowLayout(AppText text, AppColors colors) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ..._mainColumn(text),
        const SizedBox(height: 12),
        SizedBox(height: 320, child: _history(text, colors)),
      ],
    );
  }

  /// The camera, the sentence under it, and the guesses and the test when shown.
  List<Widget> _mainColumn(AppText text) {
    return [
      CameraView(connection: _connection, text: text),
      const SizedBox(height: 12),
      SentenceCard(
        words: [for (final word in _sentence) text.word(word.label)],
        text: text,
        onSpeak: _speakSentence,
        onUndo: _words.isEmpty ? null : _undo,
        onNew: () => setState(() => _sentenceStart = _words.length),
      ),
      if (_showGuesses) ...[
        const SizedBox(height: 12),
        Predictions(state: _connection.state, text: text),
      ],
      if (_test case final test?) ...[
        const SizedBox(height: 12),
        TestCard(
          key: ObjectKey(test),
          test: test,
          text: text,
          onClose: _closeTest,
        ),
      ],
    ];
  }

  /// Every word shown this session, newest at the bottom.
  Widget _history(AppText text, AppColors colors) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: panelDecoration(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
            child: Text(
              text.history,
              style: TextStyle(
                color: colors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: _words.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        text.emptyChat,
                        style: TextStyle(color: colors.muted),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _historyScroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _words.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: WordBubble(word: _words[i], text: text),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One translated word in the history.
class WordBubble extends StatelessWidget {
  const WordBubble({super.key, required this.word, required this.text});

  final Word word;
  final AppText text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.bubble,
        borderRadius: const BorderRadiusDirectional.only(
          topStart: Radius.circular(4),
          topEnd: Radius.circular(16),
          bottomStart: Radius.circular(16),
          bottomEnd: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text.word(word.label),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            '${word.time} · ${(word.confidence * 100).round()}%',
            style: TextStyle(color: colors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
