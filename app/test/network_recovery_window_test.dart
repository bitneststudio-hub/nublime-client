import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/features/connection/model/network_recovery_window.dart';

void main() {
  group('looksLikeNetworkLoss', () {
    test('recognises the health monitor failure text verbatim', () {
      // XrayVpnService.terminateFailedAttempt(a, "healthLost", "data path lost", "HEALTH_LOST")
      expect(NetworkRecoveryWindow.looksLikeNetworkLoss('data path lost'), isTrue);
      expect(NetworkRecoveryWindow.looksLikeNetworkLoss('unknown - data path lost'), isTrue);
      expect(NetworkRecoveryWindow.looksLikeNetworkLoss('No address associated with hostname'), isTrue);
      expect(NetworkRecoveryWindow.looksLikeNetworkLoss('Failed host lookup: x.example'), isTrue);
    });

    test('does not treat service failures as network loss', () {
      expect(NetworkRecoveryWindow.looksLikeNetworkLoss('invalid config'), isFalse);
      expect(NetworkRecoveryWindow.looksLikeNetworkLoss('authentication failed'), isFalse);
      expect(NetworkRecoveryWindow.looksLikeNetworkLoss(null), isFalse);
      expect(NetworkRecoveryWindow.looksLikeNetworkLoss(''), isFalse);
    });
  });

  group('NetworkRecoveryWindow', () {
    test('holds the failure back only when the device is offline AND it is a network loss', () {
      final w = NetworkRecoveryWindow();
      expect(w.onFailureOffline(networkReachable: false, detail: 'data path lost'), isTrue);
      expect(w.isArmed, isTrue);

      final online = NetworkRecoveryWindow();
      expect(online.onFailureOffline(networkReachable: true, detail: 'data path lost'), isFalse,
          reason: 'a reachable network means the failure is genuine and must be shown');
      expect(online.isArmed, isFalse);

      final other = NetworkRecoveryWindow();
      expect(other.onFailureOffline(networkReachable: false, detail: 'invalid config'), isFalse,
          reason: 'only network-loss failures are eligible for silent recovery');
      expect(other.isArmed, isFalse);
    });

    test('reconnects exactly once per armed outage', () {
      final w = NetworkRecoveryWindow();
      w.onFailureOffline(networkReachable: false, detail: 'data path lost');
      expect(w.onNetworkReachable(), isTrue);
      expect(w.isArmed, isFalse);
      expect(w.onNetworkReachable(), isFalse, reason: 'no second reconnect without a new failure');
      expect(w.attempts, 1);
    });

    test('gives up after maxAttempts so a flapping network surfaces to the user', () {
      final w = NetworkRecoveryWindow(maxAttempts: 3);
      for (var i = 0; i < 3; i++) {
        expect(w.onFailureOffline(networkReachable: false, detail: 'data path lost'), isTrue);
        expect(w.onNetworkReachable(), isTrue);
      }
      expect(w.attempts, 3);
      expect(w.onFailureOffline(networkReachable: false, detail: 'data path lost'), isFalse,
          reason: 'the fourth failure must reach the dialog path');
    });

    test('a user stop cancels the pending retry', () {
      final w = NetworkRecoveryWindow();
      w.onFailureOffline(networkReachable: false, detail: 'data path lost');
      w.cancel();
      expect(w.isArmed, isFalse);
      expect(w.onNetworkReachable(), isFalse);
    });

    test('a new session resets the attempt budget', () {
      final w = NetworkRecoveryWindow(maxAttempts: 1);
      w.onFailureOffline(networkReachable: false, detail: 'data path lost');
      w.onNetworkReachable();
      expect(w.onFailureOffline(networkReachable: false, detail: 'data path lost'), isFalse);
      w.onSessionStarted();
      expect(w.attempts, 0);
      expect(w.onFailureOffline(networkReachable: false, detail: 'data path lost'), isTrue);
    });
  });
}
