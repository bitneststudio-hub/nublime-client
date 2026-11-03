// WO-5 / WO-6 — stats rate math + single-node group contract.
//
// Stats semantics pinned here (device: hev TProxyGetStats cumulative counters, 1 s push):
//   S1 first sample            → rates 0, totals = counters
//   S2 steady growth           → rate = Δbytes*1000/Δms (integer)
//   S3 idle                    → rate 0, totals preserved
//   S4 counter reset (restart) → rate 0 that tick, baseline rebased, next delta correct
//   S5 non-monotonic timestamp → rate 0, baseline updated
//   S6 large counters (5 GiB)  → no overflow/truncation
//   S7 reset() drops the baseline
//
// Group contract pinned here (WO-6): single node → exactly ONE group with ONE item,
// selected flags consistent; the node comes from routing rules → route.final → first vless;
// no vless outbound → null (never a fabricated node).

import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/nublimecore/model/stats_rate_calculator.dart';
import 'package:nublime/nublimecore/node_group_builder.dart';

Map<String, dynamic> _config({
  List<dynamic>? rules,
  Object? routeFinal,
  bool withVless = true,
}) =>
    <String, dynamic>{
      'outbounds': <dynamic>[
        if (withVless)
          <String, dynamic>{
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': <String, dynamic>{
              'vnext': <dynamic>[
                <String, dynamic>{'address': '203.0.113.9', 'port': 8443},
              ],
            },
          },
        <String, dynamic>{'tag': 'direct', 'protocol': 'freedom'},
      ],
      if (rules != null)
        'routing': <String, dynamic>{'rules': rules},
      if (routeFinal != null) 'route': <String, dynamic>{'final': routeFinal},
    };

void main() {
  group('StatsRateCalculator (WO-5)', () {
    test('S1 first sample: rates 0, totals from counters', () {
      final c = StatsRateCalculator();
      final s = c.next(txBytes: 1000, rxBytes: 5000, tsMs: 1000);
      expect(s.uplink, 0);
      expect(s.downlink, 0);
      expect(s.uplinkTotal, 1000);
      expect(s.downlinkTotal, 5000);
    });

    test('S2 steady growth over 2s → bytes/s', () {
      final c = StatsRateCalculator();
      c.next(txBytes: 1000, rxBytes: 5000, tsMs: 1000);
      final s = c.next(txBytes: 3000, rxBytes: 25000, tsMs: 3000);
      expect(s.uplink, 1000); // +2000 B in 2000 ms
      expect(s.downlink, 10000); // +20000 B in 2000 ms
      expect(s.uplinkTotal, 3000);
      expect(s.downlinkTotal, 25000);
    });

    test('S3 idle keeps rate 0 and totals', () {
      final c = StatsRateCalculator();
      c.next(txBytes: 1000, rxBytes: 5000, tsMs: 1000);
      final s = c.next(txBytes: 1000, rxBytes: 5000, tsMs: 2000);
      expect(s.uplink, 0);
      expect(s.downlink, 0);
      expect(s.uplinkTotal, 1000);
      expect(s.downlinkTotal, 5000);
    });

    test('S4 counter reset → 0 that tick, rebased, next delta correct', () {
      final c = StatsRateCalculator();
      c.next(txBytes: 100000, rxBytes: 900000, tsMs: 1000);
      final resetTick = c.next(txBytes: 50, rxBytes: 100, tsMs: 2000);
      expect(resetTick.uplink, 0, reason: 'a reset must never surface as traffic');
      expect(resetTick.downlink, 0);
      expect(resetTick.uplinkTotal, 50);
      final next = c.next(txBytes: 1050, rxBytes: 1100, tsMs: 3000);
      expect(next.uplink, 1000);
      expect(next.downlink, 1000);
    });

    test('S5 non-monotonic timestamp → 0 rate', () {
      final c = StatsRateCalculator();
      c.next(txBytes: 0, rxBytes: 0, tsMs: 5000);
      final s = c.next(txBytes: 999999, rxBytes: 999999, tsMs: 4000);
      expect(s.uplink, 0);
      expect(s.downlink, 0);
    });

    test('S6 large counters (5 GiB) do not truncate', () {
      const fiveGiB = 5 * 1024 * 1024 * 1024;
      final c = StatsRateCalculator();
      c.next(txBytes: fiveGiB, rxBytes: fiveGiB, tsMs: 1000);
      final s = c.next(txBytes: fiveGiB + 1048576, rxBytes: fiveGiB, tsMs: 2000);
      expect(s.uplink, 1048576); // 1 MiB in 1 s
      expect(s.uplinkTotal, fiveGiB + 1048576);
    });

    test('S7 reset() drops the baseline', () {
      final c = StatsRateCalculator();
      c.next(txBytes: 10, rxBytes: 10, tsMs: 1000);
      c.reset();
      final s = c.next(txBytes: 500, rxBytes: 500, tsMs: 2000);
      expect(s.uplink, 0, reason: 'after reset the next sample is a first sample');
      expect(s.downlink, 0);
    });
  });

  group('NodeGroupBuilder (WO-6)', () {
    test('G1 single vless outbound → one group, one item, selected', () {
      final g = NodeGroupBuilder.fromXrayConfig(_config());
      expect(g, isNotNull);
      expect(g!.items.length, 1);
      expect(g.selected, 'proxy');
      expect(g.items.single.tag, 'proxy');
      expect(g.items.single.isSelected, isTrue);
      expect(g.items.single.host, '203.0.113.9');
      expect(g.items.single.port, 8443);
    });

    test('G2 routing rule naming another vless tag wins', () {
      final cfg = <String, dynamic>{
        'outbounds': <dynamic>[
          <String, dynamic>{'tag': 'node-a', 'protocol': 'vless', 'settings': <String, dynamic>{'vnext': <dynamic>[{'address': '198.51.100.1', 'port': 443}]}},
          <String, dynamic>{'tag': 'node-b', 'protocol': 'vless', 'settings': <String, dynamic>{'vnext': <dynamic>[{'address': '198.51.100.2', 'port': 8443}]}},
        ],
        'routing': <String, dynamic>{
          'rules': <dynamic>[
            <String, dynamic>{'type': 'field', 'outboundTag': 'node-b'},
          ],
        },
      };
      final g = NodeGroupBuilder.fromXrayConfig(cfg);
      expect(g!.selected, 'node-b');
      expect(g.items.single.host, '198.51.100.2');
    });

    test('G3 route.final is honoured when no rule matches', () {
      final cfg = <String, dynamic>{
        'outbounds': <dynamic>[
          <String, dynamic>{'tag': 'first', 'protocol': 'vless', 'settings': <String, dynamic>{'vnext': <dynamic>[{'address': '192.0.2.7', 'port': 443}]}},
          <String, dynamic>{'tag': 'second', 'protocol': 'vless', 'settings': <String, dynamic>{'vnext': <dynamic>[{'address': '192.0.2.8', 'port': 443}]}},
        ],
        'route': <String, dynamic>{'final': 'second'},
      };
      expect(NodeGroupBuilder.fromXrayConfig(cfg)!.selected, 'second');
    });

    test('G4 no vless outbound → null (never a fabricated node)', () {
      expect(NodeGroupBuilder.fromXrayConfig(_config(withVless: false)), isNull);
    });

    test('G5 flat server/server_port shape is supported', () {
      final cfg = <String, dynamic>{
        'outbounds': <dynamic>[
          <String, dynamic>{'tag': 'proxy', 'protocol': 'vless', 'server': '203.0.113.44', 'server_port': 443},
        ],
      };
      final g = NodeGroupBuilder.fromXrayConfig(cfg);
      expect(g!.items.single.host, '203.0.113.44');
      expect(g.items.single.port, 443);
    });
  });
}
