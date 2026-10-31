import 'package:flutter_test/flutter_test.dart';
import 'package:sign_translator/accuracy_test.dart';

void main() {
  late DateTime now;

  void wait(Duration duration) => now = now.add(duration);

  AccuracyTest create({Future<String> Function(List<Trial>)? save}) =>
      AccuracyTest(
        ['hello', 'yes'],
        save: save ?? (_) async => 'logs/test.json',
        clock: () => now,
      );

  setUp(() => now = DateTime(2026, 9, 14, 12));

  test('asks for every sign twice, in two rounds', () {
    expect(create().trials.map((trial) => trial.expected), [
      'hello',
      'yes',
      'hello',
      'yes',
    ]);
  });

  test('ignores a word shown right after the prompt', () {
    final test = create();
    wait(const Duration(milliseconds: 300));
    test.answer('hello');
    expect(test.phase, TestPhase.waiting);

    wait(const Duration(milliseconds: 900));
    test.answer('hello');
    expect(test.phase, TestPhase.feedback);
    expect(test.current.shown, 'hello');
    expect(test.current.seconds, 1.2);
  });

  test('counts no word in time as missed, then moves on after the pause', () {
    final test = create();
    wait(trialTime);
    test.tick();
    expect(test.phase, TestPhase.feedback);
    expect(test.current.shown, isNull);

    test.answer('hello'); // during the pause: ignored
    expect(test.current.shown, isNull);

    wait(feedbackTime);
    test.tick();
    expect(test.index, 1);
    expect(test.phase, TestPhase.waiting);
    expect(test.current.started, now);
    expect(test.trials.first.toJson()['started'], '2026-09-14T12:00:00.000');
  });

  test('saves the trials after the last sign', () async {
    List<Trial>? saved;
    final test = create(
      save: (trials) async {
        saved = trials;
        return 'logs/test-1.json';
      },
    );
    // Asked for: hello, yes, hello, yes.
    for (final shown in ['hello', 'no', 'hello', 'yes']) {
      wait(const Duration(seconds: 2));
      test.answer(shown);
      wait(feedbackTime);
      test.tick();
    }
    expect(test.phase, TestPhase.done);
    expect(test.correctCount, 3);

    await Future<void>.delayed(Duration.zero);
    expect(saved, hasLength(4));
    expect(test.savedFile, 'logs/test-1.json');
    expect(test.saveFailed, isFalse);
  });

  test('reports a failed save', () async {
    final test = create(save: (_) async => throw Exception('server down'));
    for (var i = 0; i < 4; i++) {
      wait(trialTime);
      test.tick();
      wait(feedbackTime);
      test.tick();
    }
    await Future<void>.delayed(Duration.zero);
    expect(test.saveFailed, isTrue);
    expect(test.savedFile, isNull);
  });
}
