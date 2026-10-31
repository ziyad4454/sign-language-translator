import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accuracy_test.dart';
import 'strings.dart';
import 'theme.dart';

const _bigWord = TextStyle(fontSize: 38, fontWeight: FontWeight.w700);

/// The accuracy test on screen: the sign to make with a countdown, whether the
/// translator got it, and the score at the end.
class TestCard extends StatefulWidget {
  const TestCard({
    super.key,
    required this.test,
    required this.text,
    required this.onClose,
  });

  final AccuracyTest test;
  final AppText text;
  final VoidCallback onClose;

  @override
  State<TestCard> createState() => _TestCardState();
}

class _TestCardState extends State<TestCard> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      widget.test.tick();
      if (widget.test.phase == TestPhase.waiting) {
        setState(() {}); // move the countdown
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: widget.test,
      builder: (context, _) {
        final test = widget.test;
        final text = widget.text;
        final total = test.trials.length;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          decoration: panelDecoration(
            colors,
            borderColor: colors.accent,
            borderWidth: 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      text.progress(math.min(test.index + 1, total), total),
                      style: TextStyle(color: colors.muted),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onClose,
                    child: Text(
                      test.phase == TestPhase.done ? text.close : text.stopTest,
                    ),
                  ),
                ],
              ),
              ...switch (test.phase) {
                TestPhase.waiting => _waiting(test, text, colors),
                TestPhase.feedback => _feedback(test, text, colors),
                TestPhase.done => _summary(test, text, colors),
              },
            ],
          ),
        );
      },
    );
  }

  List<Widget> _waiting(AccuracyTest test, AppText text, AppColors colors) {
    final left = test.secondsLeft;
    final muted = TextStyle(color: colors.muted);
    return [
      Text(text.prompt, style: muted),
      Text(text.word(test.current.expected), style: _bigWord),
      const SizedBox(height: 4),
      Text(text.waiting(left.ceil()), style: muted),
      const SizedBox(height: 6),
      ProgressBar(
        fraction: left / trialTime.inSeconds,
        color: colors.accent,
        height: 6,
      ),
    ];
  }

  List<Widget> _feedback(AccuracyTest test, AppText text, AppColors colors) {
    final trial = test.current;
    final (message, color) = trial.shown == null
        ? (text.missed, colors.warn)
        : trial.correct
        ? (text.correct, colors.good)
        : (text.wrong(text.word(trial.shown!)), colors.bad);
    return [
      Text(text.word(trial.expected), style: _bigWord),
      Text(
        message,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      const SizedBox(height: 4),
      Text(text.rest, style: TextStyle(color: colors.muted)),
    ];
  }

  List<Widget> _summary(AccuracyTest test, AppText text, AppColors colors) {
    const bold = TextStyle(fontWeight: FontWeight.w600);
    final saved = test.savedFile != null
        ? text.saved(test.savedFile!)
        : test.saveFailed
        ? text.notSaved
        : text.saving;
    return [
      Text(
        text.result(test.correctCount, test.trials.length),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        border: TableBorder(horizontalInside: BorderSide(color: colors.line)),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              _cell(Text(text.wordColumn, style: bold)),
              _cell(Text(text.attemptsColumn, style: bold)),
            ],
          ),
          for (final label in test.order)
            TableRow(
              children: [
                _cell(Text(text.word(label))),
                _cell(
                  Wrap(
                    spacing: 14,
                    children: [
                      for (final trial in test.trials.where(
                        (trial) => trial.expected == label,
                      ))
                        Text(
                          trial.correct
                              ? '✓'
                              : '✗ ${trial.shown == null ? text.noWord : text.word(trial.shown!)}',
                          style: TextStyle(
                            color: trial.correct ? colors.good : colors.bad,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(saved, style: TextStyle(color: colors.muted)),
    ];
  }

  Widget _cell(Widget child) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 16, 6),
    child: child,
  );
}
