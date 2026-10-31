import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Where app.py is running. In the browser that's the address the app was opened
/// from. Anywhere else, build with `--dart-define=SERVER=http://<computer>:8000`.
Uri serverAddress() {
  const configured = String.fromEnvironment('SERVER');
  return configured.isEmpty ? Uri.base : Uri.parse(configured);
}

const _reconnectDelay = Duration(milliseconds: 1500);

/// One of the model's top guesses.
class Prediction {
  const Prediction(this.label, this.probability);

  final String label;
  final double probability;
}

/// What the translator is doing right now.
class EngineState {
  const EngineState(
    this.status, {
    this.top = const [],
    this.error,
    this.camera = true,
    this.hint,
  });

  factory EngineState.fromJson(Map<String, dynamic> json) => EngineState(
    json['status'] as String,
    top: [
      for (final pair in json['top'] as List)
        Prediction(pair[0] as String, (pair[1] as num).toDouble()),
    ],
    error: json['error'] as String?,
    camera: json['camera'] as bool? ?? true,
    hint: json['hint'] as String?,
  );

  /// starting, watching, no_hands, no_body, camera_off or error, from app.py;
  /// offline while there's no connection to it.
  final String status;
  final List<Prediction> top;
  final String? error;

  /// Whether the camera is on. The camera button turns it off and on again.
  final bool camera;

  /// What the signer should change about where they sit: move_closer, move_back,
  /// center_yourself, or null.
  final String? hint;
}

/// A translated word.
class Word {
  const Word(this.label, this.confidence, this.time);

  factory Word.fromJson(Map<String, dynamic> json) => Word(
    json['label'] as String,
    (json['confidence'] as num).toDouble(),
    json['time'] as String,
  );

  final String label;
  final double confidence;
  final String time; // HH:MM:SS on the computer running app.py
}

/// The connection to app.py. Keeps its two WebSockets open, reconnecting whenever
/// they drop (for example while app.py restarts), and turns their messages into
/// values the page listens to.
class EngineConnection {
  EngineConnection(this.server);

  final Uri server;
  final state = ValueNotifier(const EngineState('starting'));
  final picture = ValueNotifier<ui.Image?>(null); // the latest camera picture
  final translations = ValueNotifier<Map<String, Map<String, String>?>>(
    const {},
  );
  final testOrder = ValueNotifier<List<String>>(const []);
  final _words = StreamController<Word>.broadcast();

  final _channels = <WebSocketChannel>{};
  bool _closed = false;
  Uint8List? _nextPicture;
  bool _decoding = false;

  Stream<Word> get words => _words.stream;

  void start() {
    _keepOpen(
      '/ws',
      _onEvent,
      onDrop: () => state.value = const EngineState('offline'),
    );
    _keepOpen('/ws/video', _onPicture);
  }

  void close() {
    _closed = true;
    for (final channel in [..._channels]) {
      channel.sink.close();
    }
    _words.close();
  }

  /// Turns the camera off, which closes it so its light goes out, or on again.
  Future<void> setCamera(bool on) async {
    final response = await http.post(
      _address(server.scheme, '/api/camera'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'on': on}),
    );
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}');
    }
  }

  /// Saves a finished accuracy test in app.py's logs folder. Returns the file name.
  Future<String> saveTestResults(List<Map<String, Object?>> trials) async {
    final response = await http.post(
      _address(server.scheme, '/api/test-results'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'trials': trials}),
    );
    if (response.statusCode != 200) {
      throw http.ClientException(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['file']
        as String;
  }

  Uri _address(String scheme, String path) =>
      Uri(scheme: scheme, host: server.host, port: server.port, path: path);

  Future<void> _keepOpen(
    String path,
    void Function(dynamic message) onMessage, {
    VoidCallback? onDrop,
  }) async {
    final address = _address(server.scheme == 'https' ? 'wss' : 'ws', path);
    while (!_closed) {
      final channel = WebSocketChannel.connect(address);
      _channels.add(channel);
      try {
        await channel.ready;
        await for (final message in channel.stream) {
          onMessage(message);
        }
      } catch (_) {
        // app.py isn't running, or the connection dropped: try again below.
      } finally {
        _channels.remove(channel);
      }
      if (_closed) return;
      onDrop?.call();
      await Future<void>.delayed(_reconnectDelay);
    }
  }

  void _onEvent(dynamic message) {
    if (_closed || message is! String) return;
    final json = jsonDecode(message) as Map<String, dynamic>;
    switch (json['type']) {
      case 'setup':
        translations.value = {
          for (final MapEntry(:key, :value)
              in (json['translations'] as Map<String, dynamic>).entries)
            key: value == null ? null : Map<String, String>.from(value as Map),
        };
        testOrder.value = List<String>.from(json['testOrder'] as List);
      case 'state':
        state.value = EngineState.fromJson(json);
      case 'word':
        _words.add(Word.fromJson(json));
    }
  }

  void _onPicture(dynamic message) {
    if (_closed || message is! List<int>) return;
    // Pictures can arrive faster than they're decoded: only the newest waiting
    // one is kept.
    _nextPicture = message is Uint8List ? message : Uint8List.fromList(message);
    if (!_decoding) _decodePictures();
  }

  Future<void> _decodePictures() async {
    _decoding = true;
    while (_nextPicture != null && !_closed) {
      final bytes = _nextPicture!;
      _nextPicture = null;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        final previous = picture.value;
        picture.value = frame.image;
        // The image widget holds its own reference while it still shows it.
        previous?.dispose();
      } catch (_) {
        // A damaged picture: skip it.
      }
    }
    _decoding = false;
  }
}
