import 'dart:async';

/// Manages the inactivity timer for an authenticated owner session.
///
/// This class deliberately does not perform authentication itself. The caller
/// decides when an owner session becomes active and what should happen when
/// the inactivity limit is reached.
class OwnerSessionManager {
  OwnerSessionManager({
    required this.onTimeout,
    this.inactivityLimit = const Duration(minutes: 10),
  }) {
    if (inactivityLimit <= Duration.zero) {
      throw ArgumentError.value(
        inactivityLimit,
        'inactivityLimit',
        'Must be greater than zero.',
      );
    }
  }

  final Duration inactivityLimit;
  final void Function() onTimeout;

  Timer? _timer;
  bool _isActive = false;
  bool _isDisposed = false;

  bool get isActive => _isActive;

  /// Starts monitoring an already-authenticated owner session.
  void start() {
    if (_isDisposed) {
      throw StateError('OwnerSessionManager has been disposed.');
    }

    _isActive = true;
    _scheduleTimeout();
  }

  /// Restarts the inactivity countdown after user activity.
  void recordActivity() {
    if (!_isActive || _isDisposed) return;
    _scheduleTimeout();
  }

  /// Stops monitoring without invoking [onTimeout].
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isActive = false;
  }

  /// Cancels the timer permanently.
  void dispose() {
    cancel();
    _isDisposed = true;
  }

  void _scheduleTimeout() {
    _timer?.cancel();
    _timer = Timer(inactivityLimit, () {
      _timer = null;
      if (!_isActive || _isDisposed) return;

      _isActive = false;
      onTimeout();
    });
  }
}
