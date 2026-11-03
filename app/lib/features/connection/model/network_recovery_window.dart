/// Decides whether a failed session should be retried automatically once the device gets
/// its network back, instead of being reported to the user as a service failure.
///
/// Device evidence (2026-10-30, Redmi M2103K19I, 4.1.17): with the tunnel up, airplane mode
/// for 10 s and back left the app on a raw "意外失败 / unknown - data path lost" dialog and
/// disconnected — the user had to tap connect again. Losing the network is not a service
/// failure: it must not be presented as one, and the tunnel has to come back by itself when
/// the network does.
///
/// Kept as a pure state machine (same style as [StopSuppressionWindow]) so the exact
/// sequences are unit-testable without mounting the Riverpod notifier.
library;

class NetworkRecoveryWindow {
  NetworkRecoveryWindow({
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
  });

  /// How many silent reconnects a single outage may trigger before the failure is surfaced.
  /// Bounded on purpose: a network that keeps dying is a real problem the user must see.
  final int maxAttempts;

  /// Delay between "network is back" and the reconnect attempt (lets Android settle the
  /// default network / DNS before the tunnel is rebuilt).
  final Duration retryDelay;

  /// Substrings that mean "the device lost its network", as opposed to "the service failed".
  /// The health monitor reports the first one verbatim when its data-path probe fails
  /// (`XrayVpnService.terminateFailedAttempt(a, "healthLost", "data path lost", "HEALTH_LOST")`).
  static const List<String> lossMarkers = <String>[
    'data path lost',
    'no tun interface present',
    'network is unreachable',
    'no address associated with hostname',
    'failed host lookup',
  ];

  bool _armed = false;
  int _attempts = 0;

  bool get isArmed => _armed;
  int get attempts => _attempts;

  /// True when [detail] reads like a lost network rather than a broken service.
  static bool looksLikeNetworkLoss(String? detail) {
    if (detail == null || detail.isEmpty) return false;
    final String s = detail.toLowerCase();
    return lossMarkers.any(s.contains);
  }

  /// Called when a failure terminal arrives. Returns true when this failure must be held
  /// back (no dialog) and recovery should wait for the network.
  ///
  /// [networkReachable] is the caller's probe result: when the device still has a working
  /// network the failure is genuine and must be shown, so the answer is always false.
  bool onFailureOffline({required bool networkReachable, required String? detail}) {
    if (networkReachable) return false;
    if (!looksLikeNetworkLoss(detail)) return false;
    if (_attempts >= maxAttempts) return false;
    _armed = true;
    return true;
  }

  /// Called by the watcher once the probe reports a working network again.
  /// Returns true exactly once per armed outage: the caller reconnects then.
  bool onNetworkReachable() {
    if (!_armed) return false;
    _armed = false;
    _attempts += 1;
    return true;
  }

  /// A user-initiated stop, an explicit connect, or a newer session cancels the pending
  /// recovery — the user's intent outranks the automatic retry.
  void cancel() {
    _armed = false;
  }

  /// The next successful session resets the budget, so an unrelated outage later gets its
  /// own attempts instead of inheriting the previous count.
  void onSessionStarted() {
    _armed = false;
    _attempts = 0;
  }
}
