import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Represents this local device's cryptographic identity (Ed25519).
class DeviceIdentity {
  final String deviceId;
  final SimpleKeyPair keyPair;
  final List<int> publicKeyBytes;

  DeviceIdentity({
    required this.deviceId,
    required this.keyPair,
    required this.publicKeyBytes,
  });

  static final Ed25519 _algorithm = Ed25519();
  static const _storageKey = 'hotshare_ed25519_seed';
  static const _storage = FlutterSecureStorage();

  /// Loads an existing identity from secure storage or generates a new one.
  static Future<DeviceIdentity> loadOrCreate() async {
    final existingSeedHex = await _storage.read(key: _storageKey);
    SimpleKeyPair keyPair;

    if (existingSeedHex != null && existingSeedHex.isNotEmpty) {
      final seed = _hexDecode(existingSeedHex);
      keyPair = await _algorithm.newKeyPairFromSeed(seed);
    } else {
      keyPair = await _algorithm.newKeyPair();
      final seed = await keyPair.extractPrivateKeyBytes();
      await _storage.write(key: _storageKey, value: _hexEncode(seed));
    }

    final pubKey = await keyPair.extractPublicKey();
    final pubKeyBytes = pubKey.bytes;

    // deviceId = Base32 of the first 16 bytes of SHA-256(publicKey)
    final hash = crypto.sha256.convert(pubKeyBytes).bytes.sublist(0, 16);
    final deviceId = _base32Encode(hash).toLowerCase();

    return DeviceIdentity(
      deviceId: deviceId,
      keyPair: keyPair,
      publicKeyBytes: pubKeyBytes,
    );
  }

  /// Signs [message] using this device's private key.
  Future<List<int>> sign(List<int> message) async {
    final signature = await _algorithm.sign(message, keyPair: keyPair);
    return signature.bytes;
  }

  /// Verifies a [signature] against [message] and [publicKeyBytes].
  static Future<bool> verify({
    required List<int> message,
    required List<int> signature,
    required List<int> publicKeyBytes,
  }) async {
    final pubKey = SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    );
    final sig = Signature(signature, publicKey: pubKey);
    return _algorithm.verify(message, signature: sig);
  }

  // Helper Base32 encoding (RFC 4648 without padding)
  static String _base32Encode(List<int> bytes) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final output = StringBuffer();
    int buffer = 0;
    int bitsLeft = 0;

    for (final b in bytes) {
      buffer = (buffer << 8) | (b & 0xFF);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        final index = (buffer >> (bitsLeft - 5)) & 0x1F;
        bitsLeft -= 5;
        output.write(chars[index]);
      }
    }

    if (bitsLeft > 0) {
      final index = (buffer << (5 - bitsLeft)) & 0x1F;
      output.write(chars[index]);
    }

    return output.toString();
  }

  static String _hexEncode(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _hexDecode(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }
}
