import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/message.dart';

enum RelayState { disconnected, connecting, connected }

class RelayService {
  final void Function(ChatMessage) onMessage;
  final void Function(RelayState) onStateChange;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  String _serverUrl = '';
  String _username = '';
  String _room = '';
  String _relayKey = '';

  RelayState _state = RelayState.disconnected;
  RelayState get state => _state;

  RelayService({required this.onMessage, required this.onStateChange});

  void connect(String serverUrl, String username, String room, {String relayKey = ''}) {
    _serverUrl = serverUrl;
    _username = username;
    _room = room;
    _relayKey = relayKey;
    _reconnectTimer?.cancel();
    _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed) return;
    _setState(RelayState.connecting);
    _sub?.cancel();
    try {
      final uri = Uri.parse(
        '$_serverUrl/ws?username=${Uri.encodeComponent(_username)}&room=${Uri.encodeComponent(_room)}',
      );
      final headers = _relayKey.isNotEmpty
          ? {'Authorization': 'Bearer $_relayKey'}
          : <String, dynamic>{};
      final ws = await WebSocket.connect(uri.toString(), headers: headers);
      _channel = IOWebSocketChannel(ws);
      _sub = _channel!.stream.listen(
        _onData,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
      _setState(RelayState.connected);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      final msg = ChatMessage.fromJson(map);
      if (msg.user.isEmpty || msg.text.isEmpty) return;
      onMessage(msg);
    } catch (_) {}
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _setState(RelayState.disconnected);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _doConnect);
  }

  void _setState(RelayState s) {
    _state = s;
    onStateChange(s);
  }

  void send(String username, String text, String room) {
    if (_state != RelayState.connected) return;
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final payload = jsonEncode({'user': username, 'text': text, 'ts': ts, 'to': null});
    try {
      _channel?.sink.add(payload);
    } catch (_) {}
  }

  void changeRoom(String room) {
    _room = room;
    _sub?.cancel();
    _channel?.sink.close();
    _doConnect();
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
  }
}
