import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_relay.dart';

class StorageService {
  static const _keyUsername = 'rc_username';
  static const _keyServerUrl = 'rc_server_url';
  static const _keyRoom = 'rc_room';
  static const _keyRelayKey = 'rc_relay_key';
  static const _keyMessageKey = 'rc_message_key';
  static const _keySavedRelays = 'rc_saved_relays';
  static const _keyThemeMode   = 'rc_theme_mode';
  static const _keyContacts    = 'rc_contacts';

  static const defaultServer = 'wss://relay.root-chat.com';
  static const defaultRoom = 'public';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String get username => _prefs.getString(_keyUsername) ?? '';
  String get serverUrl => _prefs.getString(_keyServerUrl) ?? defaultServer;
  String get room => _prefs.getString(_keyRoom) ?? defaultRoom;
  String get relayKey => _prefs.getString(_keyRelayKey) ?? '';
  String get messageKey => _prefs.getString(_keyMessageKey) ?? '';

  List<SavedRelay> get savedRelays {
    final raw = _prefs.getString(_keySavedRelays);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => SavedRelay.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setUsername(String v) => _prefs.setString(_keyUsername, v);
  Future<void> setServerUrl(String v) => _prefs.setString(_keyServerUrl, v);
  Future<void> setRoom(String v) => _prefs.setString(_keyRoom, v);
  Future<void> setRelayKey(String v) => _prefs.setString(_keyRelayKey, v);
  Future<void> setMessageKey(String v) => _prefs.setString(_keyMessageKey, v);
  String get themeMode => _prefs.getString(_keyThemeMode) ?? 'dark';
  Future<void> setThemeMode(String v) => _prefs.setString(_keyThemeMode, v);

  Future<void> setSavedRelays(List<SavedRelay> relays) =>
      _prefs.setString(_keySavedRelays, jsonEncode(relays.map((r) => r.toJson()).toList()));

  List<String> get contacts {
    final raw = _prefs.getString(_keyContacts);
    if (raw == null || raw.isEmpty) return [];
    try { return (jsonDecode(raw) as List).cast<String>(); } catch (_) { return []; }
  }

  Future<void> setContacts(List<String> v) =>
      _prefs.setString(_keyContacts, jsonEncode(v));
}
