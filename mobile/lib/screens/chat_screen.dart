import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../services/relay_service.dart';
import '../services/storage_service.dart';
import 'settings_screen.dart';

// ── colours ──────────────────────────────────────────────────────────────────
const _bg       = Color(0xFF0D0D0D);
const _surface  = Color(0xFF141414);
const _border   = Color(0xFF1A1A1A);
const _dim      = Color(0xFF2E2E2E);
const _dimmer   = Color(0xFF1E1E1E);
const _muted    = Color(0xFF444444);
const _body     = Color(0xFF888888);
const _amber    = Color(0xFFFFAA00);
const _green    = Color(0xFF4A7C59);
const _red      = Color(0xFF6B2020);
const _own      = Color(0xFF555555);

class ChatScreen extends StatefulWidget {
  final StorageService storage;

  const ChatScreen({super.key, required this.storage});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages   = <_DisplayMessage>[];
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  late RelayService _relay;
  RelayState _connState = RelayState.disconnected;
  Set<String> _onlineUsers = {};
  int? _latencyMs;
  Timer? _healthTimer;

  String get _username => widget.storage.username;
  String get _room     => widget.storage.room;
  String get _server   => widget.storage.serverUrl;

  String get _httpBase => _server
      .replaceFirst('wss://', 'https://')
      .replaceFirst('ws://', 'http://');

  @override
  void initState() {
    super.initState();
    _relay = RelayService(onMessage: _onMessage, onStateChange: _onStateChange);
    _connect();
  }

  void _connect() {
    _relay.connect(_server, _username, _room, relayKey: widget.storage.relayKey);
  }

  void _onStateChange(RelayState s) {
    if (!mounted) return;
    setState(() => _connState = s);
    if (s == RelayState.connected) {
      _appendSys('connected to $_server');
      _appendSys('joined [$_room]');
      setState(() => _onlineUsers = {_username});
      _startHealthPoll();
    } else if (s == RelayState.disconnected) {
      _appendSys('connection lost  —  reconnecting in 3s...');
      _healthTimer?.cancel();
    }
  }

  void _onMessage(ChatMessage msg) {
    if (!mounted) return;
    if (msg.isSystem) {
      _appendSys(msg.text);
      final joined = RegExp(r'^(.+) joined$').firstMatch(msg.text);
      final left   = RegExp(r'^(.+) left$').firstMatch(msg.text);
      if (joined != null) setState(() => _onlineUsers.add(joined.group(1)!));
      if (left   != null) setState(() => _onlineUsers.remove(left.group(1)!));
      return;
    }
    final own     = msg.user == _username;
    final mention = !own && msg.text.toLowerCase().contains('@${_username.toLowerCase()}');
    setState(() {
      _messages.add(_DisplayMessage(
        user: msg.user, text: msg.text, ts: msg.ts,
        own: own, mention: mention,
      ));
    });
    _scrollToBottom();
  }

  void _appendSys(String text) {
    setState(() {
      _messages.add(_DisplayMessage(user: '·', text: text, ts: _now(), sys: true));
    });
    _scrollToBottom();
  }

  void _startHealthPoll() {
    _healthTimer?.cancel();
    _pollHealth();
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollHealth());
  }

  Future<void> _pollHealth() async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      final resp = await http.get(
        Uri.parse('$_httpBase/health'),
        headers: {'Cache-Control': 'no-store'},
      ).timeout(const Duration(seconds: 4));
      final ms   = DateTime.now().millisecondsSinceEpoch - t0;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final users = (data['rooms']?[_room] as List?)?.cast<String>();
      if (mounted) {
        setState(() {
          _latencyMs = ms;
          if (users != null) _onlineUsers = users.toSet();
        });
      }
    } catch (_) {}
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _connState != RelayState.connected) return;
    final ts = _now();
    _relay.send(_username, text, _room);
    setState(() {
      _messages.add(_DisplayMessage(user: _username, text: text, ts: ts, own: true));
    });
    _inputCtrl.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _now() {
    final d = DateTime.now();
    return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  void _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(
        storage: widget.storage,
        onSaved: () {
          _relay.dispose();
          _relay = RelayService(onMessage: _onMessage, onStateChange: _onStateChange);
          _messages.clear();
          _onlineUsers.clear();
          _connect();
        },
      ),
    ));
  }

  // ── users drawer ─────────────────────────────────────────────────────────

  void _showUsersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const Border(top: BorderSide(color: _border)),
      builder: (_) => _UsersSheet(users: _onlineUsers, self: _username, room: _room),
    );
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _relay.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _StatusBar(
              connState: _connState,
              username: _username,
              room: _room,
              server: _server,
              latencyMs: _latencyMs,
              onSettingsTap: _openSettings,
              onUsersTap: _showUsersSheet,
              userCount: _onlineUsers.length,
            ),
            Expanded(child: _MessageList(messages: _messages, scrollCtrl: _scrollCtrl)),
            _InputRow(
              ctrl: _inputCtrl,
              focus: _inputFocus,
              enabled: _connState == RelayState.connected,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

// ── sub-widgets ───────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final RelayState connState;
  final String username, room, server;
  final int? latencyMs;
  final VoidCallback onSettingsTap, onUsersTap;
  final int userCount;

  const _StatusBar({
    required this.connState, required this.username, required this.room,
    required this.server, required this.latencyMs,
    required this.onSettingsTap, required this.onUsersTap,
    required this.userCount,
  });

  Color get _dotColor => switch (connState) {
    RelayState.connected    => _green,
    RelayState.connecting   => _muted,
    RelayState.disconnected => _red,
  };

  @override
  Widget build(BuildContext context) {
    final mono = GoogleFonts.jetBrainsMono(fontSize: 12, color: _muted);
    return Container(
      height: 40,
      color: _surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // connection dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 6, height: 6,
            decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          // status text
          Expanded(
            child: Text(
              connState == RelayState.connected
                  ? '$username  ·  $room'
                  : connState == RelayState.connecting
                      ? 'connecting...'
                      : 'disconnected',
              style: mono,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // latency
          if (latencyMs != null)
            Text('${latencyMs}ms', style: mono.copyWith(color: _dim)),
          const SizedBox(width: 12),
          // users button
          GestureDetector(
            onTap: onUsersTap,
            child: Text('● $userCount', style: mono.copyWith(color: _dim)),
          ),
          const SizedBox(width: 14),
          // settings button
          GestureDetector(
            onTap: onSettingsTap,
            child: Text('···', style: mono.copyWith(color: _dim, letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<_DisplayMessage> messages;
  final ScrollController scrollCtrl;

  const _MessageList({required this.messages, required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (_, i) => _MessageRow(msg: messages[i]),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final _DisplayMessage msg;
  const _MessageRow({super.key, required this.msg});

  @override
  Widget build(BuildContext context) {
    final userColor = msg.sys ? const Color(0xFF3A3A3A)
        : msg.own  ? _own
        : _amber;
    final bodyColor = msg.sys     ? const Color(0xFF3A3A3A)
        : msg.mention ? _amber
        : msg.own     ? _own
        : _body;
    final tsColor = _dim;

    final mono = GoogleFonts.jetBrainsMono(fontSize: 13, height: 1.65);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Text(msg.ts, style: mono.copyWith(color: tsColor, fontSize: 12)),
          ),
          Text(msg.user, style: mono.copyWith(color: userColor)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg.text, style: mono.copyWith(color: bodyColor)),
          ),
        ],
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  final TextEditingController ctrl;
  final FocusNode focus;
  final bool enabled;
  final VoidCallback onSend;

  const _InputRow({required this.ctrl, required this.focus, required this.enabled, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final mono = GoogleFonts.jetBrainsMono(fontSize: 13, color: _body);
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text('> ', style: mono.copyWith(color: _dim)),
          Expanded(
            child: TextField(
              controller: ctrl,
              focusNode: focus,
              enabled: enabled,
              style: mono,
              cursorColor: _own,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: enabled ? 'message...' : 'connecting...',
                hintStyle: mono.copyWith(color: const Color(0xFF252525)),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => onSend(),
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.send,
            ),
          ),
          GestureDetector(
            onTap: enabled ? onSend : null,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text('↵', style: mono.copyWith(color: enabled ? _dim : const Color(0xFF1E1E1E), fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersSheet extends StatelessWidget {
  final Set<String> users;
  final String self, room;

  const _UsersSheet({required this.users, required this.self, required this.room});

  @override
  Widget build(BuildContext context) {
    final sorted = [...users]..sort();
    final mono = GoogleFonts.jetBrainsMono(fontSize: 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('in room  ·  $room',
              style: mono.copyWith(color: _dim, fontSize: 11, letterSpacing: 1.5)),
        ),
        const Divider(color: _border, height: 1),
        ...sorted.map((u) => ListTile(
              dense: true,
              leading: Text('●', style: mono.copyWith(color: u == self ? _green : _green, fontSize: 8)),
              title: Text(u, style: mono.copyWith(color: u == self ? _own : _muted)),
            )),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _DisplayMessage {
  final String user, text, ts;
  final bool own, sys, mention;

  _DisplayMessage({
    required this.user, required this.text, required this.ts,
    this.own = false, this.sys = false, this.mention = false,
  });
}
