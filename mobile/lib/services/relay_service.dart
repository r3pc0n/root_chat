import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/message.dart';
import 'crypto_service.dart';

enum RelayState { disconnected, connecting, connected }

class RelayService {
  static const _bgChannel  = MethodChannel('com.rootchat/background');
  static const _msgChannel = EventChannel('com.rootchat/messages');

  final void Function(ChatMessage) onMessage;
  final void Function(RelayState, {bool resumed}) onStateChange;

  StreamSubscription? _sub;
  bool _disposed = false;

  String _serverUrl  = '';
  String _username   = '';
  String _room       = '';
  String _relayKey   = '';
  String _messageKey = '';

  final _crypto = CryptoService();

  // Messages that arrive before crypto is initialised are queued here.
  bool _cryptoReady = false;
  final _pendingRaw = <String>[];

  RelayState _state = RelayState.disconnected;
  RelayState get state => _state;

  RelayService({required this.onMessage, required this.onStateChange}) {
    _sub = _msgChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) {},
    );
  }

  Future<void> connect(
    String serverUrl,
    String username,
    String room, {
    String relayKey   = '',
    String messageKey = '',
  }) async {
    // Discard stale pending messages from a previous session.
    _pendingRaw.clear();
    _cryptoReady = false;

    _serverUrl  = serverUrl;
    _username   = username;
    _room       = room;
    _relayKey   = relayKey;
    _messageKey = messageKey;

    await _crypto.init(messageKey, room);
    _cryptoReady = true;

    // Decrypt and deliver any messages that arrived while crypto was initialising.
    final pending = List<String>.of(_pendingRaw);
    _pendingRaw.clear();
    for (final raw in pending) {
      await _processMessage(raw);
    }

    _bgChannel.invokeMethod('connectRelay', {
      'url':        serverUrl,
      'room':       room,
      'username':   username,
      'relayKey':   relayKey,
      'messageKey': messageKey,
    });
  }

  Future<void> _onEvent(dynamic raw) async {
    if (raw is! String || _disposed) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;

      // State events from Kotlin are always processed immediately.
      if (map.containsKey('_state')) {
        _setState(
          _parseState(map['_state'] as String),
          resumed: map['resume'] == true,
        );
        return;
      }

      // Chat message — queue if crypto is not ready yet.
      if (!_cryptoReady) {
        _pendingRaw.add(raw);
        return;
      }

      await _processMessage(raw);
    } catch (_) {}
  }

  Future<void> _processMessage(String raw) async {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final msg = ChatMessage.fromJson(map);
      if (msg.user.isEmpty || msg.text.isEmpty) return;
      if (_crypto.enabled && !msg.isSystem) {
        final decrypted = await _crypto.decrypt(msg.text);
        onMessage(ChatMessage(user: msg.user, text: decrypted, ts: msg.ts, to: msg.to));
      } else {
        onMessage(msg);
      }
    } catch (_) {}
  }

  Future<void> send(String username, String text, String room) async {
    if (_state != RelayState.connected) return;
    final now = DateTime.now();
    final ts  = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final wireText = _crypto.enabled ? await _crypto.encrypt(text) : text;
    final payload  = jsonEncode({'user': username, 'text': wireText, 'ts': ts, 'to': null});
    _bgChannel.invokeMethod('sendMessage', {'json': payload});
  }

  void changeRoom(String room) {
    connect(_serverUrl, _username, room, relayKey: _relayKey, messageKey: _messageKey);
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    // The Kotlin service keeps the WebSocket alive for background notifications.
  }

  void _setState(RelayState s, {bool resumed = false}) {
    // Suppress duplicate non-resume state events (e.g. connectRelay echoing "connected"
    // when the service is already connected to the same endpoint).
    if (_state == s && !resumed) return;
    _state = s;
    onStateChange(s, resumed: resumed);
  }

  RelayState _parseState(String s) => switch (s) {
    'connected'  => RelayState.connected,
    'connecting' => RelayState.connecting,
    _            => RelayState.disconnected,
  };
}
