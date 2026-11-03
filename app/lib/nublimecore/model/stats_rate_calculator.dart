// WO-5: converts CUMULATIVE traffic counters (pushed by XrayVpnService every second via
// EventChannel 'com.nublime.vpn/stats') into the StatsInfo shape the existing UI consumes.
//
// Contract pinned by test/r31c_stats_and_group_test.dart (S1-S7):
//   - first sample            → rates 0, totals = counters (no bogus burst)
//   - steady growth           → rate = Δbytes * 1000 / Δms, integer truncating
//   - idle (no growth)        → rate 0, totals preserved
//   - counter RESET (service restart / hev restart → counters restart at 0)
//                             → rate 0 for that tick, baseline rebased (never a negative or
//                               astronomically large spike: a 64-bit wrap or reset must not
//                               surface as traffic)
//   - non-monotonic timestamp → rate 0 (clock/elapsed jitter), baseline updated
//
// Counters are int64 end-to-end (Kotlin Long → Dart int); no truncation risk for realistic
// volumes (2^63 bytes ≫ any tunnel's lifetime traffic).

import 'package:nublime/nublimecore/model/core_types.dart';

class StatsRateCalculator {
  int? _lastTx;
  int? _lastRx;
  int? _lastAtMs;

  /// Feed one cumulative sample; returns the StatsInfo to render for this tick.
  StatsInfo next({required int txBytes, required int rxBytes, required int tsMs}) {
    final prevTx = _lastTx;
    final prevRx = _lastRx;
    final prevAt = _lastAtMs;

    var txRate = 0;
    var rxRate = 0;
    if (prevTx != null && prevRx != null && prevAt != null) {
      final dtMs = tsMs - prevAt;
      final dTx = txBytes - prevTx;
      final dRx = rxBytes - prevRx;
      if (dtMs > 0) {
        // Negative delta = counter reset (service/hev restart). Never render it as traffic.
        if (dTx >= 0) txRate = dTx * 1000 ~/ dtMs;
        if (dRx >= 0) rxRate = dRx * 1000 ~/ dtMs;
      }
    }

    _lastTx = txBytes;
    _lastRx = rxBytes;
    _lastAtMs = tsMs;

    return StatsInfo(
      uplink: txRate,
      downlink: rxRate,
      uplinkTotal: txBytes,
      downlinkTotal: rxBytes,
    );
  }

  /// Drop the baseline (project-level reset: e.g. a new session starts).
  void reset() {
    _lastTx = null;
    _lastRx = null;
    _lastAtMs = null;
  }
}
