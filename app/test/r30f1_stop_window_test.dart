// R30-F1 — StopSuppressionWindow semantics (user-stop suppression window).
//
// Device evidence driving this contract (2026-10-20, 1/2 repro): a user disconnect can
// produce TWO terminal events for one session (health failure terminal + clean stop
// terminal); the old one-shot flag (F5) was consumed by whichever terminal arrived
// first, so the late second terminal hit the dialog path → spurious
// "意外失败 unknown - data path lost" after a perfectly successful disconnect.
//
// The window replaces the one-shot flag:
//   W1  arm → clean terminal → LATE failure terminal  → suppressed (the device race)
//   W2  arm → failure terminal (only)                 → suppressed
//   W3  arm → clean → late failure → next Connecting → new failure → NOT suppressed (F5)
//   W4  no arm → failure                              → NOT suppressed (real failures show)
//   W5  arm (abort path) → late failure               → suppressed
//   W6  arm → Connecting closes window (state check)

import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/features/connection/model/connection_failure.dart';
import 'package:nublime/features/connection/model/connection_status.dart';
import 'package:nublime/features/connection/model/stop_suppression_window.dart';

void main() {
  const lostFailure = ConnectionFailure.unexpected('unknown - data path lost');
  final cleanTerminal = const Disconnected(null);
  final lateFailureTerminal = const Disconnected(lostFailure);

  test('W1: arm → clean terminal → LATE failure terminal → suppressed (device race)', () {
    final w = StopSuppressionWindow()..armForUserStop();
    // clean terminal does NOT close or consume the window
    w.onStatusEvent(cleanTerminal);
    expect(w.isArmed, isTrue, reason: 'clean terminal must not consume the window');
    expect(w.suppressesFailureTerminal(lateFailureTerminal), isTrue,
        reason: 'the late second terminal of the double-terminal race must be suppressed');
  });

  test('W2: arm → failure terminal only → suppressed', () {
    final w = StopSuppressionWindow()..armForUserStop();
    expect(w.suppressesFailureTerminal(lateFailureTerminal), isTrue);
  });

  test('W3: arm → clean → late failure → next Connecting closes window → new failure shows (F5)', () {
    final w = StopSuppressionWindow()..armForUserStop();
    w.onStatusEvent(cleanTerminal);
    expect(w.suppressesFailureTerminal(lateFailureTerminal), isTrue);
    // a NEW session starts — the window must close BEFORE its failures can occur
    w.onStatusEvent(const Connecting());
    expect(w.isArmed, isFalse, reason: 'F5: the stale window must not suppress the next session');
    final newSessionFailure = const Disconnected(
        ConnectionFailure.unexpected('genuine failure of session B'));
    expect(w.suppressesFailureTerminal(newSessionFailure), isFalse,
        reason: 'F5 guarantee: the next session\'s genuine failure must surface');
  });

  test('W4: no arm → failure → NOT suppressed (real failures always show)', () {
    final w = StopSuppressionWindow();
    expect(w.suppressesFailureTerminal(lateFailureTerminal), isFalse);
  });

  test('W5: abort path arms the same window → late failure suppressed', () {
    final w = StopSuppressionWindow()..armForUserStop(); // abortConnection arms via the same call
    w.onStatusEvent(const Disconnecting());
    expect(w.isArmed, isTrue, reason: 'Disconnecting (teardown start) must not close the window');
    expect(w.suppressesFailureTerminal(lateFailureTerminal), isTrue);
  });

  test('W6: Connected also closes the window (either new-session signal)', () {
    final w = StopSuppressionWindow()..armForUserStop();
    w.onStatusEvent(const Connected());
    expect(w.isArmed, isFalse);
  });
}
