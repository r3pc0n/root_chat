import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  SecretKey? _key;
  bool get enabled => _key != null;

  Future<void> init(String password, String room) async {
    if (password.isEmpty) {
      _key = null;
      return;
    }
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    _key = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: utf8.encode(room),
    );
  }

  Future<String> encrypt(String plaintext) async {
    final key = _key;
    if (key == null) return plaintext;
    final algorithm = Chacha20.poly1305Aead();
    final rng = Random.secure();
    final nonce = List.generate(12, (_) => rng.nextInt(256));
    final secretBox = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    final combined = Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64.encode(combined);
  }

  Future<String> decrypt(String ciphertext) async {
    final key = _key;
    if (key == null) return ciphertext;
    try {
      final bytes = base64.decode(ciphertext);
      if (bytes.length < 28) return '[encrypted — key mismatch]';
      final nonce = bytes.sublist(0, 12);
      final cipherText = bytes.sublist(12, bytes.length - 16);
      final mac = bytes.sublist(bytes.length - 16);
      final algorithm = Chacha20.poly1305Aead();
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
      final decrypted = await algorithm.decrypt(secretBox, secretKey: key);
      return utf8.decode(decrypted);
    } catch (_) {
      return '[encrypted — key mismatch]';
    }
  }
}
