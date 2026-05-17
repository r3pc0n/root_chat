import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _keyUsername = 'rc_username';
  static const _keyServerUrl = 'rc_server_url';
  static const _keyRoom = 'rc_room';
  static const _keyRelayKey = 'rc_relay_key';

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

  Future<void> setUsername(String v) => _prefs.setString(_keyUsername, v);
  Future<void> setServerUrl(String v) => _prefs.setString(_keyServerUrl, v);
  Future<void> setRoom(String v) => _prefs.setString(_keyRoom, v);
  Future<void> setRelayKey(String v) => _prefs.setString(_keyRelayKey, v);
}
