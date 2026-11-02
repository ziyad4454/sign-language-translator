import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sign_guide.dart';
import 'strings.dart';
import 'theme.dart';

/// On a wide screen the text stays this wide, so its lines are easy to read.
const _readingWidth = 720.0;

/// How to use the app, how to make each sign, and the frequently asked questions.
/// Opened from the top bar.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key, required this.text});

  final AppText text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: colors.panel,
          surfaceTintColor: Colors.transparent,
          title: Text(
            text.help,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            tooltip: text.close,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: TabBar(
            labelColor: colors.accent,
            unselectedLabelColor: colors.muted,
            tabs: [
              Tab(text: text.howToUse),
              Tab(text: text.signs),
              Tab(text: text.faq),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Column(
              children: [
                for (final (i, (title, details)) in text.steps.indexed)
                  _Step(number: i + 1, title: title, details: details),
              ],
            ),
            _Column(
              children: [
                Text(
                  text.signsSource,
                  style: TextStyle(color: colors.muted, height: 1.5),
                ),
                for (final guide in signGuides.values)
                  _Fold(
                    title: guide.name(text.language),
                    subtitle: guide.bothHands ? text.bothHands : text.oneHand,
                    answer: guide.steps(text.language),
                    action: _VideoButton(guide: guide, text: text),
                  ),
              ],
            ),
            _Column(
              children: [
                for (final (question, answer) in text.questions)
                  _Fold(title: question, answer: answer),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A scrolling list of boxes, in the middle of the page.
class _Column extends StatelessWidget {
  const _Column({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _readingWidth),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => children[i],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.details,
  });

  final int number;
  final String title;
  final String details;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: panelDecoration(colors),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            child: Text(
              '$number',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  details,
                  style: TextStyle(color: colors.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A box that opens when pressed: a question, or a sign.
class _Fold extends StatelessWidget {
  const _Fold({
    required this.title,
    required this.answer,
    this.subtitle,
    this.action,
  });

  final String title;
  final String answer;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: colors.accent,
        collapsedIconColor: colors.muted,
        textColor: colors.ink,
        collapsedTextColor: colors.ink,
        expandedAlignment: AlignmentDirectional.centerStart,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: TextStyle(color: colors.muted)),
        children: [
          Text(answer, style: TextStyle(color: colors.muted, height: 1.5)),
          ?action,
        ],
      ),
    );
  }
}

/// Opens the sign's page in the dictionary, which has the video.
class _VideoButton extends StatelessWidget {
  const _VideoButton({required this.guide, required this.text});

  final SignGuide guide;
  final AppText text;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        guide.videoPage,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Told below, the same as when the page didn't open.
    }
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(text.videoFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextButton.icon(
        onPressed: () => _open(context),
        icon: const Icon(Icons.play_circle_outline),
        label: Text(text.watchVideo),
      ),
    );
  }
}
