import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_translator/help_page.dart';
import 'package:sign_translator/sign_guide.dart';
import 'package:sign_translator/strings.dart';
import 'package:sign_translator/theme.dart';

const _translations = {
  'hello': {'en': 'Hello', 'ar': 'السلام عليكم'},
  'water': {'en': 'Water', 'ar': 'ماء'},
  'nothing': null,
};

Widget _app(AppText text) => MaterialApp(
  theme: buildTheme(Brightness.light),
  home: Directionality(
    textDirection: text.isArabic ? TextDirection.rtl : TextDirection.ltr,
    child: HelpPage(text: text),
  ),
);

void main() {
  test('known words leave out "nothing"', () {
    const text = AppText(Language.en, _translations);
    expect(text.knownWords, ['Hello', 'Water']);
  });

  test('both languages have the same steps and questions', () {
    const arabic = AppText(Language.ar, _translations);
    const english = AppText(Language.en, _translations);
    expect(arabic.steps.length, english.steps.length);
    expect(arabic.questions.length, english.questions.length);
  });

  test('the words question works before the app has connected', () {
    const text = AppText(Language.en, {});
    expect(text.questions.first.$2, contains('once the translator'));
  });

  test('every word in labels_translation.json has a guide with its names', () {
    final file = File('../labels_translation.json').readAsStringSync();
    final words = (jsonDecode(file) as Map<String, dynamic>)..remove('nothing');
    expect(signGuides.keys, words.keys);
    words.forEach((label, names) {
      expect(signGuides[label]!.arabicName, names['ar']);
      expect(signGuides[label]!.englishName, names['en']);
    });
  });

  test('every guide links to its own video', () {
    final videos = signGuides.values.map((guide) => guide.video).toSet();
    expect(videos.length, signGuides.length);
  });

  testWidgets('a sign opens its steps and video button', (tester) async {
    const text = AppText(Language.ar, {});
    await tester.pumpWidget(_app(text));
    await tester.tap(find.text(text.signs));
    await tester.pumpAndSettle();
    final guide = signGuides['hello']!;
    await tester.tap(find.text(guide.arabicName));
    await tester.pumpAndSettle();
    expect(find.text(guide.arabic), findsOneWidget);
    expect(find.text(text.watchVideo), findsOneWidget);
  });

  for (final language in Language.values) {
    testWidgets('a question opens its answer, in ${language.name}', (
      tester,
    ) async {
      final text = AppText(language, _translations);
      await tester.pumpWidget(_app(text));
      expect(find.text(text.steps.first.$1), findsOneWidget);

      await tester.tap(find.text(text.faq));
      await tester.pumpAndSettle();
      final (question, answer) = text.questions.first;
      await tester.tap(find.text(question));
      await tester.pumpAndSettle();
      expect(find.text(answer), findsOneWidget);
    });
  }
}
