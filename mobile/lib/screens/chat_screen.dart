import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../models/saved_relay.dart';
import '../services/relay_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final StorageService storage;

  const ChatScreen({super.key, required this.storage});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _messages   = <_DisplayMessage>[];
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  static const _bgChannel = MethodChannel('com.rootchat/background');

  late RelayService _relay;
  RelayState _connState = RelayState.disconnected;
  Set<String> _onlineUsers = {};
  int? _latencyMs;
  Timer? _healthTimer;

  bool _isInBackground = false;
  bool _reconnectedInBackground = false;

  // Room we came from before entering a DM (in-memory only).
  String _previousRoom = '';

  String get _username => widget.storage.username;
  String get _room     => widget.storage.room;
  String get _server   => widget.storage.serverUrl;

  // DM helpers
  bool get _isDm => _room.startsWith('dm_');
  String? get _dmPeer {
    if (!_isDm) return null;
    final parts = _room.substring(3).split('_');
    return parts.firstWhere((p) => p != _username, orElse: () => parts.first);
  }

  String get _httpBase => _server
      .replaceFirst('wss://', 'https://')
      .replaceFirst('ws://', 'http://');

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _relay = RelayService(onMessage: _onMessage, onStateChange: _onStateChange);
    _connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _isInBackground = true;
      _bgChannel.invokeMethod('setBackground', {'value': true}).catchError((_) {});
    } else if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      _bgChannel.invokeMethod('setBackground', {'value': false}).catchError((_) {});
      if (_reconnectedInBackground) {
        _appendSys('reconnected');
        _reconnectedInBackground = false;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _healthTimer?.cancel();
    _relay.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── connection ────────────────────────────────────────────────────────────

  void _connect() {
    _relay.connect(
      _server, _username, _room,
      relayKey:   widget.storage.relayKey,
      messageKey: widget.storage.messageKey,
    );
  }

  void _onStateChange(RelayState s, {bool resumed = false}) {
    if (!mounted) return;
    setState(() => _connState = s);
    if (s == RelayState.connected) {
      if (_isInBackground) {
        _reconnectedInBackground = true;
      } else if (!resumed) {
        _appendSys('connected to $_server');
        _appendSys('joined [$_room]');
      }
      setState(() => _onlineUsers = {_username});
      _startHealthPoll();
    } else if (s == RelayState.disconnected) {
      if (!_isInBackground && !resumed) {
        _appendSys('connection lost  —  reconnecting...');
      }
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

  // ── health poll ───────────────────────────────────────────────────────────

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

  // ── send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _connState != RelayState.connected) return;
    final ts = _now();
    _inputCtrl.clear();
    await _relay.send(_username, text, _room);
    if (!mounted) return;
    setState(() {
      _messages.add(_DisplayMessage(user: _username, text: text, ts: ts, own: true));
    });
    _scrollToBottom();
  }

  // ── DM ────────────────────────────────────────────────────────────────────

  void _startDm(String peer) {
    if (!_isDm) _previousRoom = _room;
    final sorted = [_username, peer]..sort();
    _switchToRoom('dm_${sorted[0]}_${sorted[1]}');
    // Add to contacts if not already saved
    final contacts = widget.storage.contacts;
    if (!contacts.contains(peer)) {
      widget.storage.setContacts([...contacts, peer]);
    }
  }

  void _backFromDm() {
    final dest = _previousRoom.isNotEmpty ? _previousRoom : StorageService.defaultRoom;
    _previousRoom = '';
    _switchToRoom(dest);
  }

  Future<void> _switchToRoom(String room) async {
    await widget.storage.setRoom(room);
    _relay.dispose();
    setState(() {
      _relay = RelayService(onMessage: _onMessage, onStateChange: _onStateChange);
      _messages.clear();
      _onlineUsers.clear();
      _latencyMs = null;
    });
    _connect();
  }

  // ── relay picker & settings ───────────────────────────────────────────────

  void _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(
        storage: widget.storage,
        onSaved: () {
          _previousRoom = '';
          _relay.dispose();
          _relay = RelayService(onMessage: _onMessage, onStateChange: _onStateChange);
          _messages.clear();
          _onlineUsers.clear();
          _connect();
        },
      ),
    ));
  }

  void _showRelayPicker() {
    final relays = widget.storage.savedRelays;
    if (relays.isEmpty) { _openSettings(); return; }
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) => _RelayPickerSheet(
        relays: relays,
        onSelect: (r) {
          Navigator.of(ctx).pop();
          _switchRelay(r);
        },
      ),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    );
  }

  Future<void> _switchRelay(SavedRelay r) async {
    await widget.storage.setServerUrl(r.url);
    await widget.storage.setRoom(r.room);
    await widget.storage.setRelayKey(r.relayKey);
    await widget.storage.setMessageKey(r.messageKey);
    _previousRoom = '';
    _relay.dispose();
    setState(() {
      _relay = RelayService(onMessage: _onMessage, onStateChange: _onStateChange);
      _messages.clear();
      _onlineUsers.clear();
      _latencyMs = null;
    });
    _connect();
  }

  // ── users sheet ───────────────────────────────────────────────────────────

  void _showUsersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.of(context).surface,
      shape: Border(top: BorderSide(color: AppTheme.of(context).border)),
      builder: (_) => _UsersSheet(
        users: _onlineUsers,
        self: _username,
        room: _room,
        storage: widget.storage,
        onStartDm: (peer) {
          Navigator.of(context).pop();
          _startDm(peer);
        },
      ),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

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

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            _StatusBar(
              connState:    _connState,
              username:     _username,
              room:         _room,
              server:       _server,
              latencyMs:    _latencyMs,
              isDm:         _isDm,
              dmPeer:       _dmPeer,
              onSettingsTap: _openSettings,
              onUsersTap:   _showUsersSheet,
              onRelayTap:   _isDm ? _backFromDm : _showRelayPicker,
              userCount:    _onlineUsers.length,
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

// ── _StatusBar ────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final RelayState connState;
  final String username, room, server;
  final int? latencyMs;
  final bool isDm;
  final String? dmPeer;
  final VoidCallback onSettingsTap, onUsersTap, onRelayTap;
  final int userCount;

  const _StatusBar({
    required this.connState, required this.username, required this.room,
    required this.server,    required this.latencyMs,
    required this.isDm,      required this.dmPeer,
    required this.onSettingsTap, required this.onUsersTap,
    required this.onRelayTap,    required this.userCount,
  });

  @override
  Widget build(BuildContext context) {
    final t    = AppTheme.of(context);
    final mono = GoogleFonts.jetBrainsMono(fontSize: 12, color: t.muted);

    final dotColor = switch (connState) {
      RelayState.connected    => t.green,
      RelayState.connecting   => t.muted,
      RelayState.disconnected => t.red,
    };

    final centerLabel = isDm
        ? '←  DM  ·  ${dmPeer ?? ''}'
        : connState == RelayState.connected
            ? '$username  ·  $room'
            : connState == RelayState.connecting
                ? 'connecting...'
                : 'disconnected';

    return Container(
      height: 40,
      color: t.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 6, height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onRelayTap,
              behavior: HitTestBehavior.opaque,
              child: Text(centerLabel, style: mono, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (latencyMs != null)
            Text('${latencyMs}ms', style: mono.copyWith(color: t.dim)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onUsersTap,
            child: Text('● $userCount', style: mono.copyWith(color: t.dim)),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: onSettingsTap,
            child: Text('···', style: mono.copyWith(color: t.dim, letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}

// ── _MessageList ──────────────────────────────────────────────────────────────

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
    final t = AppTheme.of(context);
    final userColor = msg.sys ? t.sys : msg.own ? t.own : t.amber;
    final bodyColor = msg.sys     ? t.sys
        : msg.mention ? t.amber
        : msg.own     ? t.own
        : t.body;

    final mono = GoogleFonts.jetBrainsMono(fontSize: 13, height: 1.65);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Text(msg.ts, style: mono.copyWith(color: t.dim, fontSize: 12)),
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

// ── _InputRow ─────────────────────────────────────────────────────────────────

class _InputRow extends StatelessWidget {
  final TextEditingController ctrl;
  final FocusNode focus;
  final bool enabled;
  final VoidCallback onSend;

  const _InputRow({required this.ctrl, required this.focus, required this.enabled, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final t    = AppTheme.of(context);
    final mono = GoogleFonts.jetBrainsMono(fontSize: 13, color: t.body);
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.border))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text('> ', style: mono.copyWith(color: t.dim)),
          Expanded(
            child: TextField(
              controller: ctrl,
              focusNode: focus,
              enabled: enabled,
              style: mono,
              cursorColor: t.own,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: enabled ? 'message...' : 'connecting...',
                hintStyle: mono.copyWith(color: t.subtle),
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
              child: Text('↵',
                  style: mono.copyWith(
                      color: enabled ? t.dim : t.dimmer, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _UsersSheet ───────────────────────────────────────────────────────────────

class _UsersSheet extends StatefulWidget {
  final Set<String> users;
  final String self, room;
  final StorageService storage;
  final void Function(String peer) onStartDm;

  const _UsersSheet({
    required this.users, required this.self, required this.room,
    required this.storage, required this.onStartDm,
  });

  @override
  State<_UsersSheet> createState() => _UsersSheetState();
}

class _UsersSheetState extends State<_UsersSheet> {
  late List<String> _contacts;

  @override
  void initState() {
    super.initState();
    _contacts = widget.storage.contacts;
  }

  void _toggleContact(String user) {
    final updated = List<String>.of(_contacts);
    if (_contacts.contains(user)) {
      updated.remove(user);
    } else {
      updated.add(user);
    }
    widget.storage.setContacts(updated);
    setState(() => _contacts = updated);
  }

  Future<void> _addContactManually() async {
    final t    = AppTheme.of(context);
    final ctrl = TextEditingController();
    final mono = GoogleFonts.jetBrainsMono(color: t.body, fontSize: 13);
    final name = await showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        title: Text('add contact', style: mono.copyWith(fontSize: 13)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: mono,
          cursorColor: t.muted,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'username',
            hintStyle: mono.copyWith(color: t.subtle),
            isDense: true,
            prefixText: '> ',
            prefixStyle: mono.copyWith(color: t.dim),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          autocorrect: false,
          enableSuggestions: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('cancel', style: mono.copyWith(color: t.muted, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text('add', style: mono.copyWith(color: t.green, fontSize: 12)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == widget.self) return;
    if (!_contacts.contains(name)) {
      final updated = [..._contacts, name];
      widget.storage.setContacts(updated);
      setState(() => _contacts = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t      = AppTheme.of(context);
    final mono   = GoogleFonts.jetBrainsMono(fontSize: 12);
    final sorted = [...widget.users]..sort();

    // Contacts not currently online (offline contacts)
    final offlineContacts = _contacts
        .where((c) => !widget.users.contains(c) && c != widget.self)
        .toList()..sort();

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── online section ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('in room  ·  ${widget.room}',
                style: mono.copyWith(color: t.dim, fontSize: 11, letterSpacing: 1.5)),
          ),
          Divider(color: t.border, height: 1),
          ...sorted.map((u) => _onlineRow(u, t, mono)),

          // ── contacts section ────────────────────────────────────────
          const SizedBox(height: 4),
          Divider(color: t.border, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('contacts',
                style: mono.copyWith(color: t.dim, fontSize: 11, letterSpacing: 1.5)),
          ),
          Divider(color: t.border, height: 1),
          if (_contacts.isEmpty && offlineContacts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('no contacts yet',
                  style: mono.copyWith(color: t.subtle, fontSize: 11)),
            ),
          // Online contacts (already shown above, but with contact indicator)
          ..._contacts
              .where((c) => widget.users.contains(c) && c != widget.self)
              .map((c) => _contactRow(c, online: true, t: t, mono: mono)),
          // Offline contacts
          ...offlineContacts.map((c) => _contactRow(c, online: false, t: t, mono: mono)),
          // Add contact button
          InkWell(
            onTap: _addContactManually,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('+  add contact',
                  style: mono.copyWith(color: t.saved, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _onlineRow(String user, AppThemeData t, TextStyle mono) {
    final isSelf    = user == widget.self;
    final isContact = _contacts.contains(user);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text('●  ', style: mono.copyWith(color: t.green, fontSize: 10)),
          Expanded(
            child: Text(
              user + (isSelf ? '  (you)' : ''),
              style: mono.copyWith(color: isSelf ? t.own : t.muted),
            ),
          ),
          if (!isSelf) ...[
            GestureDetector(
              onTap: () => widget.onStartDm(user),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(border: Border.all(color: t.border)),
                child: Text('DM', style: mono.copyWith(color: t.amber, fontSize: 11)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _toggleContact(user),
              child: Text(
                isContact ? '−' : '+',
                style: mono.copyWith(color: t.muted, fontSize: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactRow(String user, {required bool online, required AppThemeData t, required TextStyle mono}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(online ? '●  ' : '○  ',
              style: mono.copyWith(
                  color: online ? t.green : t.subtle, fontSize: 10)),
          Expanded(
            child: Text(user, style: mono.copyWith(color: t.muted)),
          ),
          GestureDetector(
            onTap: () => widget.onStartDm(user),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(border: Border.all(color: t.border)),
              child: Text('DM', style: mono.copyWith(color: t.amber, fontSize: 11)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _toggleContact(user),
            child: Text('×', style: mono.copyWith(color: t.muted, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

// ── _RelayPickerSheet ─────────────────────────────────────────────────────────

class _RelayPickerSheet extends StatelessWidget {
  final List<SavedRelay> relays;
  final void Function(SavedRelay) onSelect;

  const _RelayPickerSheet({required this.relays, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t    = AppTheme.of(context);
    final mono = GoogleFonts.jetBrainsMono(fontSize: 12);
    final maxHeight = MediaQuery.of(context).size.height * 0.6;
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: t.surface,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
          child: SafeArea(
            bottom: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Text('switch relay',
                          style: mono.copyWith(
                              color: t.dim, fontSize: 11, letterSpacing: 1.5)),
                    ),
                    Divider(color: t.border, height: 1),
                    ...relays.map((r) => InkWell(
                          onTap: () => onSelect(r),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Text('>  ', style: mono.copyWith(color: t.dim)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(r.name, style: mono.copyWith(color: t.body)),
                                      const SizedBox(height: 3),
                                      Text(r.url,
                                          style: mono.copyWith(
                                              color: t.dim, fontSize: 10),
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                    Divider(color: t.border, height: 1),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── _DisplayMessage ───────────────────────────────────────────────────────────

class _DisplayMessage {
  final String user, text, ts;
  final bool own, sys, mention;

  _DisplayMessage({
    required this.user, required this.text, required this.ts,
    this.own = false, this.sys = false, this.mention = false,
  });
}
