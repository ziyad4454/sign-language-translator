import 'package:flutter/material.dart';

import 'connection.dart';
import 'home_page.dart';
import 'strings.dart';
import 'theme.dart';

/// The sign language translator app. The camera, tracking and gesture model run in
/// app.py on the computer; this app shows the camera picture, the translated words,
/// and the accuracy test.
void main() {
  runApp(TranslatorApp(connection: EngineConnection(serverAddress())));
}

/// Holds the two choices that change the whole app: the language (which also sets
/// the reading direction) and light or dark mode, which follows the device until the
/// signer picks one.
class TranslatorApp extends StatefulWidget {
  const TranslatorApp({super.key, required this.connection});

  final EngineConnection connection;

  @override
  State<TranslatorApp> createState() => _TranslatorAppState();
}

class _TranslatorAppState extends State<TranslatorApp> {
  Language _language = Language.ar;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مترجم لغة الإشارة',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode,
      // Above the navigator, so menus and tooltips get the direction too.
      builder: (context, child) => Directionality(
        textDirection: _language == Language.ar
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: child!,
      ),
      home: HomePage(
        connection: widget.connection,
        language: _language,
        onLanguage: (language) => setState(() => _language = language),
        onToggleTheme: (current) => setState(
          () => _themeMode = current == Brightness.dark
              ? ThemeMode.light
              : ThemeMode.dark,
        ),
      ),
    );
  }
}
