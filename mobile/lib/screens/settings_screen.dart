import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storage;
  final VoidCallback onSaved;

  const SettingsScreen({super.key, required this.storage, required this.onSaved});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _usernameCtrl;
  late TextEditingController _serverCtrl;
  late TextEditingController _roomCtrl;
  late TextEditingController _relayKeyCtrl;

  @override
  void initState() {
    super.initState();
    _usernameCtrl  = TextEditingController(text: widget.storage.username);
    _serverCtrl    = TextEditingController(text: widget.storage.serverUrl);
    _roomCtrl      = TextEditingController(text: widget.storage.room);
    _relayKeyCtrl  = TextEditingController(text: widget.storage.relayKey);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _serverCtrl.dispose();
    _roomCtrl.dispose();
    _relayKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim();
    final server   = _serverCtrl.text.trim();
    final room     = _roomCtrl.text.trim();
    if (username.isEmpty || server.isEmpty || room.isEmpty) return;
    await widget.storage.setUsername(username);
    await widget.storage.setServerUrl(server);
    await widget.storage.setRoom(room);
    await widget.storage.setRelayKey(_relayKeyCtrl.text.trim());
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final mono = GoogleFonts.jetBrainsMono(color: const Color(0xFF888888), fontSize: 13);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        foregroundColor: const Color(0xFF555555),
        elevation: 0,
        title: Text('settings', style: GoogleFonts.jetBrainsMono(color: const Color(0xFF555555), fontSize: 14)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1E1E1E)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          _label('username'),
          const SizedBox(height: 8),
          _field(_usernameCtrl, 'your name', mono),
          const SizedBox(height: 24),
          _label('relay server'),
          const SizedBox(height: 8),
          _field(_serverCtrl, 'wss://relay.root-chat.com', mono),
          const SizedBox(height: 24),
          _label('room'),
          const SizedBox(height: 8),
          _field(_roomCtrl, 'public', mono),
          const SizedBox(height: 24),
          _label('relay key  (leave blank for public relays)'),
          const SizedBox(height: 8),
          _field(_relayKeyCtrl, 'optional', mono, obscure: true),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: _save,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              alignment: Alignment.center,
              child: Text('save  &  reconnect',
                  style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF4A7C59), fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: GoogleFonts.jetBrainsMono(
            color: const Color(0xFF2A2A2A), fontSize: 11, letterSpacing: 1.5),
      );

  Widget _field(TextEditingController ctrl, String hint, TextStyle base,
      {bool obscure = false}) =>
      Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
        ),
        child: Row(
          children: [
            Text('> ', style: base.copyWith(color: const Color(0xFF2E2E2E))),
            Expanded(
              child: TextField(
                controller: ctrl,
                style: base,
                cursorColor: const Color(0xFF555555),
                obscureText: obscure,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: base.copyWith(color: const Color(0xFF252525)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
          ],
        ),
      );
}
