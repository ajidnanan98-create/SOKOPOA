import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class OwnerCredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureOwnerCredentialStore implements OwnerCredentialStore {
  SecureOwnerCredentialStore({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class OwnerAuthService {
  OwnerAuthService({
    OwnerCredentialStore? store,
    int iterations = 310000,
  })  : _store = store ?? SecureOwnerCredentialStore(),
        _iterations = iterations;

  static final OwnerAuthService instance = OwnerAuthService();

  static const String _saltKey = 'sokopoa.owner.password.salt';
  static const String _hashKey = 'sokopoa.owner.password.hash';

  final OwnerCredentialStore _store;
  final int _iterations;

  bool _isAuthenticated = false;

  bool get isAuthenticated => _isAuthenticated;

  final Random _random = Random.secure();

  Pbkdf2 get _algorithm => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: _iterations,
        bits: 256,
      );

  Future<bool> isPasswordConfigured() async {
    final salt = await _store.read(_saltKey);
    final hash = await _store.read(_hashKey);

    return salt != null && hash != null;
  }

  Future<void> setOwnerPassword(String password) async {
    if (password.length < 10) {
      throw ArgumentError(
        'The owner password must contain at least 10 characters.',
      );
    }

    final salt = List<int>.generate(
      16,
      (_) => _random.nextInt(256),
    );

    final secretKey = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    final hash = await secretKey.extractBytes();

    await _store.write(_saltKey, base64Encode(salt));
    await _store.write(_hashKey, base64Encode(hash));

    _isAuthenticated = true;
  }

  Future<bool> authenticateOwner(String password) async {
    _isAuthenticated = false;

    final storedSalt = await _store.read(_saltKey);
    final storedHash = await _store.read(_hashKey);

    if (storedSalt == null || storedHash == null) {
      return false;
    }

    try {
      final salt = base64Decode(storedSalt);
      final expectedHash = base64Decode(storedHash);

      final secretKey = await _algorithm.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );

      final actualHash = await secretKey.extractBytes();

      if (!_constantTimeEquals(actualHash, expectedHash)) {
        return false;
      }

      _isAuthenticated = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  void lock() {
    _isAuthenticated = false;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;

    var difference = 0;

    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }

    return difference == 0;
  }
}
