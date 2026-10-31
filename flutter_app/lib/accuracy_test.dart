import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Time allowed for each sign.
const trialTime = Duration(seconds: 10);

/// A word shown this soon after the prompt still belongs to the previous sign.
const graceTime = Duration(milliseconds: 500);

/// The pause after each answer, so the hands come down before the next sign.
const feedbackTime = Duration(milliseconds: 2500);

enum TestPhase { waiting, feedback, done }

/// One requested sign, and what the translator showed for it.
class Trial {
  Trial(this.expected);

  final String expected;
  DateTime? started; // when the sign was asked for
  String? shown; // null when no word appeared in time
  double seconds = 0; // from the prompt to the word, to 0.1 s

  bool get correct => shown == expected;

  Map<String, Object?> toJson() => {
    'expected': expected,
    'started': started?.toIso8601String(),
    'shown': shown,
    'seconds': seconds,
  };
}

/// The accuracy test. Asks for every gesture in [order], in two rounds (so the same
/// word is never asked twice in a row, which the translator's same-word cooldown
/// would block), and scores the first word the translator shows for each.
///
/// Running out of time, and moving on after the pause that follows each answer,
/// happen in [tick], which the test card calls several times a second.
class AccuracyTest extends ChangeNotifier {
  AccuracyTest(this.order, {required this.save, DateTime Function()? clock})
    : trials = [
        for (var round = 0; round < 2; round++)
          for (final label in order) Trial(label),
      ],
      _clock = clock ?? DateTime.now {
    _phaseStart = _clock();
    if (trials.isNotEmpty) current.started = _phaseStart;
  }

  final List<String> order;
  final List<Trial> trials;

  /// Stores the finished trials, and returns where they were saved.
  final Future<String> Function(List<Trial> trials) save;

  final DateTime Function() _clock;
  late DateTime _phaseStart;
  bool _stopped = false;

  int index = 0;
  TestPhase phase = TestPhase.waiting;
  String? savedFile;
  bool saveFailed = false;

  Trial get current => trials[index];
  int get correctCount => trials.where((trial) => trial.correct).length;
  Duration get _elapsed => _clock().difference(_phaseStart);

  /// Seconds left to make the current sign.
  double get secondsLeft =>
      math.max(0.0, (trialTime - _elapsed).inMilliseconds / 1000);

  void tick() {
    if (_stopped) return;
    if (phase == TestPhase.waiting && _elapsed >= trialTime) {
      _record(null, trialTime);
    } else if (phase == TestPhase.feedback && _elapsed >= feedbackTime) {
      _next();
    }
  }

  /// Called with every word the translator shows.
  void answer(String label) {
    if (_stopped || phase != TestPhase.waiting) return;
    final elapsed = _elapsed;
    if (elapsed >= graceTime) _record(label, elapsed);
  }

  /// Ends the test early. Nothing is saved.
  void stop() => _stopped = true;

  void _record(String? label, Duration elapsed) {
    current
      ..shown = label
      ..seconds = (elapsed.inMilliseconds / 100).round() / 10;
    phase = TestPhase.feedback;
    _phaseStart = _clock();
    notifyListeners();
  }

  void _next() {
    if (index + 1 < trials.length) {
      index++;
      phase = TestPhase.waiting;
      _phaseStart = _clock();
      current.started = _phaseStart;
      notifyListeners();
      return;
    }
    phase = TestPhase.done;
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    try {
      savedFile = await save(trials);
    } catch (_) {
      saveFailed = true;
    }
    if (!_stopped) notifyListeners();
  }
}
