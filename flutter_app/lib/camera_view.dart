import 'package:flutter/material.dart';

import 'connection.dart';
import 'strings.dart';
import 'theme.dart';

/// A guess at or above this counts as sure (CONFIDENCE in predict_live.py).
const sureProbability = 0.7;

/// A sign guess at or above this is shown on the picture, so the signer sees what the
/// model is thinking without opening the guesses panel.
const shownGuessProbability = 0.5;

/// The camera picture from app.py with the tracking drawn on, the status, a hint about
/// where to sit, and the model's current guess. While the camera is off it says so
/// instead of showing a picture.
class CameraView extends StatelessWidget {
  const CameraView({super.key, required this.connection, required this.text});

  final EngineConnection connection;
  final AppText text;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ValueListenableBuilder(
          valueListenable: connection.state,
          builder: (context, state, _) {
            final hint = text.hint(state.hint);
            final guess = state.top.isEmpty ? null : state.top.first;
            final showGuess =
                state.camera &&
                guess != null &&
                guess.label != 'nothing' &&
                guess.probability >= shownGuessProbability;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (state.camera)
                  ValueListenableBuilder(
                    valueListenable: connection.picture,
                    builder: (context, image, _) => image == null
                        ? Center(
                            child: Text(
                              text.waitingForCamera,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          )
                        : RawImage(image: image, fit: BoxFit.contain),
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.videocam_off,
                          color: Colors.white54,
                          size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          text.status('camera_off', null),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                PositionedDirectional(
                  top: 10,
                  start: 10,
                  end: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Badge(
                        text.status(state.status, state.error),
                        color: switch (state.status) {
                          'watching' => Palette.good.withValues(alpha: 0.9),
                          'error' ||
                          'offline' => Palette.bad.withValues(alpha: 0.92),
                          _ => Colors.black.withValues(alpha: 0.65),
                        },
                      ),
                      if (state.camera && hint != null) ...[
                        const SizedBox(height: 6),
                        _Badge(
                          hint,
                          color: Palette.warn.withValues(alpha: 0.92),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showGuess)
                  PositionedDirectional(
                    bottom: 10,
                    start: 10,
                    child: _Badge(
                      '${text.word(guess.label)}  ${(guess.probability * 100).round()}%',
                      color: Colors.black.withValues(alpha: 0.65),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.message, {required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
    );
  }
}

/// The model's three most likely gestures right now, shown from the menu.
class Predictions extends StatelessWidget {
  const Predictions({super.key, required this.state, required this.text});

  final ValueNotifier<EngineState> state;
  final AppText text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: panelDecoration(colors),
      child: ValueListenableBuilder(
        valueListenable: state,
        builder: (context, state, _) => state.top.isEmpty
            ? Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  text.noPredictions,
                  style: TextStyle(color: colors.muted),
                ),
              )
            : Column(
                children: [
                  for (final prediction in state.top) _row(prediction, colors),
                ],
              ),
      ),
    );
  }

  Widget _row(Prediction prediction, AppColors colors) {
    final sure = prediction.probability >= sureProbability;
    final style = TextStyle(
      color: sure ? colors.ink : colors.muted,
      fontWeight: sure ? FontWeight.w600 : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(text.word(prediction.label), style: style),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ProgressBar(
              fraction: prediction.probability,
              color: sure ? colors.accent : colors.muted,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: Text(
              '${(prediction.probability * 100).round()}%',
              textAlign: TextAlign.end,
              style: style.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
