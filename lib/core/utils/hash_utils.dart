import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PIN hashing for the app lock. A random per-device salt is stored next to
/// the hash so equal PINs hash differently across installs.
class HashUtils {
  HashUtils._();

  /// Generates a random hex salt (16 bytes) from a secure random source.
  static String generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// SHA-256 of `salt:pin` as lowercase hex.
  static String hashPin(String salt, String pin) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  /// Constant-time-ish comparison (lengths differ -> false immediately).
  static bool verifyPin(String salt, String pin, String expectedHash) {
    final actual = hashPin(salt, pin);
    if (actual.length != expectedHash.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }
}
