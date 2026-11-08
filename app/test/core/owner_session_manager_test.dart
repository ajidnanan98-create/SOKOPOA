import 'package:flutter_test/flutter_test.dart';
import 'package:sokopoa/core/owner_session_manager.dart';

void main() {
  group('OwnerSessionManager', () {
    test('does not time out before the inactivity limit', () async {
      var timeoutCount = 0;
      final manager = OwnerSessionManager(
        inactivityLimit: const Duration(milliseconds: 80),
        onTimeout: () => timeoutCount++,
      );

      manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(manager.isActive, isTrue);
      expect(timeoutCount, 0);
      manager.dispose();
    });

    test('locks the session when the inactivity limit expires', () async {
      var timeoutCount = 0;
      final manager = OwnerSessionManager(
        inactivityLimit: const Duration(milliseconds: 40),
        onTimeout: () => timeoutCount++,
      );

      manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(manager.isActive, isFalse);
      expect(timeoutCount, 1);
      manager.dispose();
    });

    test('resets the countdown after user activity', () async {
      var timeoutCount = 0;
      final manager = OwnerSessionManager(
        inactivityLimit: const Duration(milliseconds: 100),
        onTimeout: () => timeoutCount++,
      );

      manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      manager.recordActivity();

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(manager.isActive, isTrue);
      expect(timeoutCount, 0);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(manager.isActive, isFalse);
      expect(timeoutCount, 1);
      manager.dispose();
    });

    test('cancel stops the timer without invoking the timeout', () async {
      var timeoutCount = 0;
      final manager = OwnerSessionManager(
        inactivityLimit: const Duration(milliseconds: 40),
        onTimeout: () => timeoutCount++,
      );

      manager.start();
      manager.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(manager.isActive, isFalse);
      expect(timeoutCount, 0);
      manager.dispose();
    });

    test('activity does not restart a cancelled session', () async {
      var timeoutCount = 0;
      final manager = OwnerSessionManager(
        inactivityLimit: const Duration(milliseconds: 40),
        onTimeout: () => timeoutCount++,
      );

      manager.start();
      manager.cancel();
      manager.recordActivity();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(manager.isActive, isFalse);
      expect(timeoutCount, 0);
      manager.dispose();
    });

    test('rejects a zero or negative inactivity limit', () {
      expect(
        () => OwnerSessionManager(
          inactivityLimit: Duration.zero,
          onTimeout: () {},
        ),
        throwsArgumentError,
      );
      expect(
        () => OwnerSessionManager(
          inactivityLimit: const Duration(seconds: -1),
          onTimeout: () {},
        ),
        throwsArgumentError,
      );
    });

    test('cannot be started again after disposal', () {
      final manager = OwnerSessionManager(onTimeout: () {});
      manager.dispose();

      expect(manager.start, throwsStateError);
    });
  });
}
