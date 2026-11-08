
import 'package:flutter_test/flutter_test.dart';
import 'package:sokopoa/core/owner_auth_service.dart';

class MemoryCredentialStore implements OwnerCredentialStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  group('OwnerAuthService', () {
    late MemoryCredentialStore store;
    late OwnerAuthService auth;

    setUp(() {
      store = MemoryCredentialStore();
      auth = OwnerAuthService(
        store: store,
        iterations: 10000,
      );
    });

    test('reports that no password is configured initially', () async {
      expect(await auth.isPasswordConfigured(), isFalse);
      expect(auth.isAuthenticated, isFalse);
    });

    test('creates a password and verifies it successfully', () async {
      await auth.setOwnerPassword('StrongPassword123');

      expect(await auth.isPasswordConfigured(), isTrue);
      expect(auth.isAuthenticated, isTrue);

      auth.lock();

      expect(auth.isAuthenticated, isFalse);
      expect(
        await auth.authenticateOwner('StrongPassword123'),
        isTrue,
      );
      expect(auth.isAuthenticated, isTrue);
    });

    test('rejects an incorrect password', () async {
      await auth.setOwnerPassword('StrongPassword123');
      auth.lock();

      expect(
        await auth.authenticateOwner('WrongPassword123'),
        isFalse,
      );
      expect(auth.isAuthenticated, isFalse);
    });

    test('rejects passwords shorter than ten characters', () async {
      expect(
        () => auth.setOwnerPassword('short'),
        throwsArgumentError,
      );
      expect(await auth.isPasswordConfigured(), isFalse);
    });

    test('locks an authenticated owner session', () async {
      await auth.setOwnerPassword('StrongPassword123');

      expect(auth.isAuthenticated, isTrue);

      auth.lock();

      expect(auth.isAuthenticated, isFalse);
    });

    test('stores a salted hash rather than the original password', () async {
      const password = 'StrongPassword123';

      await auth.setOwnerPassword(password);

      expect(store.values.values, isNot(contains(password)));
      expect(store.values.length, 2);
    });
  });
}
