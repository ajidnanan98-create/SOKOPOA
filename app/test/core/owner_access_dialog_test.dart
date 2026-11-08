import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sokopoa/core/owner_access_dialog.dart';
import 'package:sokopoa/core/owner_auth_service.dart';

class _MemoryCredentialStore implements OwnerCredentialStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Future<void> _openDialog(
  WidgetTester tester,
  OwnerAuthService auth,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => OwnerAccessDialog(authService: auth),
                );
              },
              child: const Text('Open owner access'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open owner access'));
  await tester.pumpAndSettle();
}

void main() {
  group('OwnerAccessDialog widget tests', () {
    late _MemoryCredentialStore store;
    late OwnerAuthService auth;

    setUp(() {
      store = _MemoryCredentialStore();
      // Lower iterations keep widget tests fast. Production remains 310,000.
      auth = OwnerAuthService(store: store, iterations: 1000);
    });

    testWidgets('shows first-time password setup fields', (tester) async {
      await _openDialog(tester, auth);

      expect(find.text('Set up owner access'), findsOneWidget);
      expect(find.text('Owner password'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(find.text('Create password'), findsOneWidget);
    });

    testWidgets('rejects a password shorter than 10 characters',
        (tester) async {
      await _openDialog(tester, auth);

      await tester.enterText(
        find.byType(TextField).at(0),
        'short123',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'short123',
      );
      await tester.tap(find.text('Create password'));
      await tester.pumpAndSettle();

      expect(
        find.text('Use at least 10 characters for your password.'),
        findsOneWidget,
      );
      expect(auth.isAuthenticated, isFalse);
    });

    testWidgets('rejects mismatched password confirmation', (tester) async {
      await _openDialog(tester, auth);

      await tester.enterText(
        find.byType(TextField).at(0),
        'StrongPass123',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'DifferentPass123',
      );
      await tester.tap(find.text('Create password'));
      await tester.pumpAndSettle();

      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(auth.isAuthenticated, isFalse);
    });

    testWidgets('creates owner credentials and closes the dialog',
        (tester) async {
      await _openDialog(tester, auth);

      await tester.enterText(
        find.byType(TextField).at(0),
        'StrongPass123',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'StrongPass123',
      );
      await tester.tap(find.text('Create password'));
      await tester.pumpAndSettle();

      expect(auth.isAuthenticated, isTrue);
      expect(find.text('Set up owner access'), findsNothing);
      expect(await auth.isPasswordConfigured(), isTrue);
    });

    testWidgets('shows an error for an incorrect existing password',
        (tester) async {
      await auth.setOwnerPassword('StrongPass123');
      auth.lock();

      await _openDialog(tester, auth);

      expect(find.text('Owner login'), findsOneWidget);
      expect(find.text('Confirm password'), findsNothing);

      await tester.enterText(
        find.byType(TextField).first,
        'WrongPassword123',
      );
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(
        find.text('Incorrect password. Please try again.'),
        findsOneWidget,
      );
      expect(auth.isAuthenticated, isFalse);
      expect(find.text('Owner login'), findsOneWidget);
    });

    testWidgets('unlocks with the correct existing password', (tester) async {
      await auth.setOwnerPassword('StrongPass123');
      auth.lock();

      await _openDialog(tester, auth);

      await tester.enterText(
        find.byType(TextField).first,
        'StrongPass123',
      );
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(auth.isAuthenticated, isTrue);
      expect(find.text('Owner login'), findsNothing);
    });

    testWidgets('cancel closes the dialog without authenticating',
        (tester) async {
      await _openDialog(tester, auth);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(auth.isAuthenticated, isFalse);
      expect(find.text('Set up owner access'), findsNothing);
    });
  });
}
