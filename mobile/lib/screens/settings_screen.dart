import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/saved_relay.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

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
  late TextEditingController _messageKeyCtrl;

  late List<SavedRelay> _savedRelays;
  late List<String> _contacts;

  @override
  void initState() {
    super.initState();
    _usernameCtrl   = TextEditingController(text: widget.storage.username);
    _serverCtrl     = TextEditingController(text: widget.storage.serverUrl);
    _roomCtrl       = TextEditingController(text: widget.storage.room);
    _relayKeyCtrl   = TextEditingController(text: widget.storage.relayKey);
    _messageKeyCtrl = TextEditingController(text: widget.storage.messageKey);
    _savedRelays    = widget.storage.savedRelays;
    _contacts       = widget.storage.contacts;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _serverCtrl.dispose();
    _roomCtrl.dispose();
    _relayKeyCtrl.dispose();
    _messageKeyCtrl.dispose();
    super.dispose();
  }

  void _loadRelay(SavedRelay r) {
    setState(() {
      _serverCtrl.text     = r.url;
      _roomCtrl.text       = r.room;
      _relayKeyCtrl.text   = r.relayKey;
      _messageKeyCtrl.text = r.messageKey;
    });
  }

  void _deleteRelay(int index) {
    final updated = [..._savedRelays]..removeAt(index);
    setState(() => _savedRelays = updated);
    widget.storage.setSavedRelays(updated);
  }

  void _removeContact(int index) {
    final updated = [..._contacts]..removeAt(index);
    setState(() => _contacts = updated);
    widget.storage.setContacts(updated);
  }

  Future<void> _addContact() async {
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
    if (name == null || name.isEmpty) return;
    if (!_contacts.contains(name)) {
      final updated = [..._contacts, name];
      setState(() => _contacts = updated);
      await widget.storage.setContacts(updated);
    }
  }

  Future<void> _saveCurrentRelay() async {
    final t = AppTheme.of(context);
    final nameCtrl = TextEditingController();
    final mono = GoogleFonts.jetBrainsMono(color: t.body, fontSize: 13);
    final name = await showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        title: Text('name this relay',
            style: GoogleFonts.jetBrainsMono(color: t.body, fontSize: 13)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: mono,
          cursorColor: t.muted,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'e.g. private relay',
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
            child: Text('cancel',
                style: GoogleFonts.jetBrainsMono(color: t.muted, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(nameCtrl.text.trim()),
            child: Text('save',
                style: GoogleFonts.jetBrainsMono(color: t.green, fontSize: 12)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final relay = SavedRelay(
      name: name,
      url: _serverCtrl.text.trim(),
      room: _roomCtrl.text.trim(),
      relayKey: _relayKeyCtrl.text.trim(),
      messageKey: _messageKeyCtrl.text.trim(),
    );
    final updated = [..._savedRelays, relay];
    setState(() => _savedRelays = updated);
    await widget.storage.setSavedRelays(updated);
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
    await widget.storage.setMessageKey(_messageKeyCtrl.text.trim());
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final mono = GoogleFonts.jetBrainsMono(color: t.body, fontSize: 13);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.surface,
        foregroundColor: t.own,
        elevation: 0,
        title: Text('settings',
            style: GoogleFonts.jetBrainsMono(color: t.own, fontSize: 14)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          // ── theme ──────────────────────────────────────────────────────
          _label('theme', t),
          const SizedBox(height: 10),
          _ThemeSelector(storage: widget.storage),
          const SizedBox(height: 28),

          // ── contacts ───────────────────────────────────────────────────
          _label('contacts', t),
          const SizedBox(height: 10),
          ..._contacts.asMap().entries.map((e) => _contactListItem(e.key, e.value, t)),
          GestureDetector(
            onTap: _addContact,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: t.saved)),
              child: Text('+ add contact',
                  style: GoogleFonts.jetBrainsMono(color: t.saved, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 28),

          // ── saved relays ───────────────────────────────────────────────
          _label('saved relays', t),
          const SizedBox(height: 10),
          ..._savedRelays.asMap().entries.map((e) => _relayListItem(e.key, e.value, t)),
          GestureDetector(
            onTap: _saveCurrentRelay,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: t.saved)),
              child: Text('+ save current',
                  style: GoogleFonts.jetBrainsMono(color: t.saved, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 28),

          // ── connection fields ──────────────────────────────────────────
          _label('username', t),
          const SizedBox(height: 8),
          _field(_usernameCtrl, 'your name', mono, t),
          const SizedBox(height: 24),
          _label('relay server', t),
          const SizedBox(height: 8),
          _field(_serverCtrl, 'wss://relay.root-chat.com', mono, t),
          const SizedBox(height: 24),
          _label('room', t),
          const SizedBox(height: 8),
          _field(_roomCtrl, 'public', mono, t),
          const SizedBox(height: 24),
          _label('relay key  (leave blank for public relays)', t),
          const SizedBox(height: 8),
          _field(_relayKeyCtrl, 'optional', mono, t, obscure: true),
          const SizedBox(height: 24),
          _label('encryption key  (leave blank for unencrypted)', t),
          const SizedBox(height: 8),
          _field(_messageKeyCtrl, 'shared secret', mono, t, obscure: true),
          const SizedBox(height: 40),

          // ── save button ────────────────────────────────────────────────
          GestureDetector(
            onTap: _save,
            child: Container(
              height: 44,
              decoration: BoxDecoration(border: Border.all(color: t.saved)),
              alignment: Alignment.center,
              child: Text('save  &  reconnect',
                  style: GoogleFonts.jetBrainsMono(color: t.green, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactListItem(int index, String name, AppThemeData t) {
    final mono = GoogleFonts.jetBrainsMono(fontSize: 12);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(border: Border.all(color: t.saved)),
      child: Row(
        children: [
          Text('○  ', style: mono.copyWith(color: t.subtle, fontSize: 10)),
          Expanded(child: Text(name, style: mono.copyWith(color: t.body))),
          GestureDetector(
            onTap: () => _removeContact(index),
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text('×', style: mono.copyWith(color: t.muted, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _relayListItem(int index, SavedRelay r, AppThemeData t) {
    final mono = GoogleFonts.jetBrainsMono(fontSize: 12);
    return GestureDetector(
      onTap: () => _loadRelay(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(border: Border.all(color: t.saved)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name, style: mono.copyWith(color: t.body)),
                  const SizedBox(height: 2),
                  Text(r.url,
                      style: mono.copyWith(color: t.saved, fontSize: 10),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _deleteRelay(index),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text('×', style: mono.copyWith(color: t.muted, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, AppThemeData t) => Text(
        text,
        style: GoogleFonts.jetBrainsMono(
            color: t.saved, fontSize: 11, letterSpacing: 1.5),
      );

  Widget _field(TextEditingController ctrl, String hint, TextStyle base,
      AppThemeData t, {bool obscure = false}) =>
      Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.saved)),
        ),
        child: Row(
          children: [
            Text('> ', style: base.copyWith(color: t.dim)),
            Expanded(
              child: TextField(
                controller: ctrl,
                style: base,
                cursorColor: t.own,
                obscureText: obscure,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: base.copyWith(color: t.subtle),
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

// ── theme selector ────────────────────────────────────────────────────────────

class _ThemeSelector extends StatelessWidget {
  final StorageService storage;
  const _ThemeSelector({required this.storage});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final notifier = AppTheme.notifierOf(context);
    final mono = GoogleFonts.jetBrainsMono(fontSize: 12);

    return Row(
      children: AppThemeData.all.map((theme) {
        final active = t.key == theme.key;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () {
              notifier.value = theme;
              storage.setThemeMode(theme.key);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: active ? t.body : t.saved),
              ),
              child: Text(
                theme.label,
                style: mono.copyWith(color: active ? t.body : t.saved),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
