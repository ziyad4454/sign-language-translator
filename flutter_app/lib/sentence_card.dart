import 'package:flutter/material.dart';

import 'strings.dart';
import 'theme.dart';

/// The words translated since the last "new sentence", in large type under the camera,
/// with buttons to say the sentence out loud, take back the last word, and start a new
/// sentence.
class SentenceCard extends StatelessWidget {
  const SentenceCard({
    super.key,
    required this.words,
    required this.text,
    required this.onSpeak,
    required this.onUndo,
    required this.onNew,
  });

  final List<String> words;
  final AppText text;
  final VoidCallback onSpeak;

  /// Null while there's no word to take back.
  final VoidCallback? onUndo;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final empty = words.isEmpty;
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 6, 10),
      decoration: BoxDecoration(
        color: colors.bubble,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              empty ? text.emptySentence : words.join(' '),
              style: TextStyle(
                fontSize: empty ? 15 : 26,
                fontWeight: empty ? FontWeight.normal : FontWeight.w700,
                color: empty ? colors.muted : colors.ink,
              ),
            ),
          ),
          IconButton(
            tooltip: text.speakSentence,
            onPressed: empty ? null : onSpeak,
            icon: const Icon(Icons.record_voice_over),
          ),
          IconButton(
            tooltip: text.undo,
            onPressed: onUndo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: text.newSentence,
            onPressed: empty ? null : onNew,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
    );
  }
}
