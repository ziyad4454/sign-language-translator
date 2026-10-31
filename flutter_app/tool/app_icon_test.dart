// Draws the app icon, Material's sign_language symbol in white on the app's teal, and
// writes it over the launcher icons for Android and the web. Run it from flutter_app/
// after changing the design, then rebuild:
//
//   flutter test tool/app_icon_test.dart
//
// It's a test only because a widget test can paint with the app's own icon font.
//
// Android 8 and later show the adaptive icon in res/mipmap-anydpi-v26/ic_launcher.xml:
// the teal from res/values/ic_launcher_background.xml behind ic_launcher_foreground.png,
// cut to the phone's own shape. Older Android versions show ic_launcher.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _teal = Color(0xFF0F766E);
const _canvas = 512.0;

enum _Style {
  /// A rounded teal square, for places that show the picture as it is.
  rounded,

  /// A full teal square that the system crops into its own shape ("maskable").
  square,

  /// Just the white symbol on nothing, for the adaptive icon's front layer. Only the
  /// middle two thirds of it are sure to stay visible after cropping.
  foreground,
}

typedef _Target = ({String path, int size, _Style style});

const _res = 'android/app/src/main/res';

const List<_Target> _targets = [
  (path: 'web/favicon.png', size: 16, style: _Style.rounded),
  (path: 'web/icons/Icon-192.png', size: 192, style: _Style.rounded),
  (path: 'web/icons/Icon-512.png', size: 512, style: _Style.rounded),
  (path: 'web/icons/Icon-maskable-192.png', size: 192, style: _Style.square),
  (path: 'web/icons/Icon-maskable-512.png', size: 512, style: _Style.square),
  (path: '$_res/mipmap-mdpi/ic_launcher.png', size: 48, style: _Style.rounded),
  (path: '$_res/mipmap-hdpi/ic_launcher.png', size: 72, style: _Style.rounded),
  (path: '$_res/mipmap-xhdpi/ic_launcher.png', size: 96, style: _Style.rounded),
  (
    path: '$_res/mipmap-xxhdpi/ic_launcher.png',
    size: 144,
    style: _Style.rounded,
  ),
  (
    path: '$_res/mipmap-xxxhdpi/ic_launcher.png',
    size: 192,
    style: _Style.rounded,
  ),
  // Adaptive icon layers are 108 dp across.
  (
    path: '$_res/mipmap-mdpi/ic_launcher_foreground.png',
    size: 108,
    style: _Style.foreground,
  ),
  (
    path: '$_res/mipmap-hdpi/ic_launcher_foreground.png',
    size: 162,
    style: _Style.foreground,
  ),
  (
    path: '$_res/mipmap-xhdpi/ic_launcher_foreground.png',
    size: 216,
    style: _Style.foreground,
  ),
  (
    path: '$_res/mipmap-xxhdpi/ic_launcher_foreground.png',
    size: 324,
    style: _Style.foreground,
  ),
  (
    path: '$_res/mipmap-xxxhdpi/ic_launcher_foreground.png',
    size: 432,
    style: _Style.foreground,
  ),
];

class _IconArt extends StatelessWidget {
  const _IconArt({required this.style});

  final _Style style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _canvas,
      height: _canvas,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style == _Style.foreground ? null : _teal,
        borderRadius: style == _Style.rounded
            ? BorderRadius.circular(_canvas * 0.22)
            : null,
      ),
      child: Icon(
        Icons.sign_language,
        color: Colors.white,
        size:
            _canvas *
            switch (style) {
              _Style.rounded => 0.64,
              _Style.square => 0.5,
              _Style.foreground => 0.46,
            },
      ),
    );
  }
}

void main() {
  testWidgets('writes the app icons', (tester) async {
    // Tests don't load the icon font by themselves; without it the symbol is a box.
    final font = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await tester.runAsync(font.load);
    final boundary = GlobalKey();
    for (final target in _targets) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: _IconArt(style: target.style),
            ),
          ),
        ),
      );
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await render.toImage(
          pixelRatio: target.size / _canvas,
        );
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(target.path).writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
