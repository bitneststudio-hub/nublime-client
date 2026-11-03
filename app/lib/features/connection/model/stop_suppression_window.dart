// R30-F1 (Astra R30 §5b/§6): user-stop suppression WINDOW.
//
// Device evidence (2026-10-20, 1/2 repro): a user disconnect can produce TWO terminal
// events for one session — the health monitor's failure terminal ("data path lost",
// published just before invalidation) AND the shutdown path's clean "Stopped". Arrival
// order at Dart is post-queue order, so the CLEAN terminal can land FIRST and consume
// the old one-shot flag (F5), leaving the late failure terminal unguarded → spurious
// "意外失败 unknown - data path lost" dialog after a perfectly successful disconnect.
//
// Window semantics (supersedes the F5 one-shot flag, keeps its guarantee):
//   - armed on user stop / user abort;
//   - closed ONLY when the NEXT session starts (Connecting/Connected) — strictly
//     bounded, so the F5 guarantee ("the next session's genuine failure always
//     shows") is preserved;
//   - while armed, failure terminals are treated as the stopping session's teardown
//     noise: suppressed from the dialog path, logged by the caller.
//
// The Kotlin side independently guarantees exactly-one terminal per session
// (Attempt.terminalPublished); this window is defense-in-depth for any residual
// late-failure source.

import 'package:nublime/features/connection/model/connection_status.dart';

class StopSuppressionWindow {
  bool _armed = false;

  bool get isArmed => _armed;

  /// A user stop / user abort arms the window.
  void armForUserStop() => _armed = true;

  /// A new session starting closes the window — failures belonging to the NEW
  /// session must surface normally (F5 guarantee).
  void onStatusEvent(ConnectionStatus event) {
    if (event is Connecting || event is Connected) _armed = false;
  }

  /// True when a failure terminal arriving NOW belongs to the stopping session's
  /// teardown (window armed) and must be suppressed from the dialog path.
  bool suppressesFailureTerminal(ConnectionStatus event) =>
      _armed && event is Disconnected && event.connectionFailure != null;
}
