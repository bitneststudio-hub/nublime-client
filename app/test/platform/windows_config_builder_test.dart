import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/platform/windows/windows_config_builder.dart';

Map<String, dynamic> _delivered({String server = '203.0.113.9', bool withLoopRule = false}) => {
      'log': {'loglevel': 'info'},
      'dns': {
        'servers': [
          {'address': 'https://1.1.1.1/dns-query'},
          {'address': '223.5.5.5'},
        ],
      },
      'inbounds': [
        {'type': 'tun', 'tag': 'android-tun', 'address': ['172.19.0.1/30']},
      ],
      'outbounds': [
        {
          'protocol': 'vless',
          'tag': 'proxy',
          'settings': {
            'vnext': [
              {'address': server, 'port': 8443, 'users': []},
            ],
          },
        },
        {'protocol': 'freedom', 'tag': 'direct'},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          if (withLoopRule)
            {'type': 'field', 'ip': ['$server/32'], 'outboundTag': 'direct'},
          {'type': 'field', 'domain': ['geosite:cn'], 'outboundTag': 'direct'},
        ],
      },
    };

void main() {
  group('buildWindowsXrayConfig', () {
    test('replaces inbounds with tun + api', () {
      final cfg = buildWindowsXrayConfig(_delivered(), logPath: 'C:/logs/xray.log');
      final inbounds = cfg['inbounds'] as List;
      expect(inbounds.map((e) => e['tag']), ['tun-in', 'api-in']);
      expect(inbounds.first['protocol'], 'tun');
      expect(inbounds.last['protocol'], 'dokodemo-door');
    });

    test('tun settings only use fields present in Xray v26.7.11', () {
      final cfg = buildWindowsXrayConfig(_delivered(), logPath: 'x.log');
      final tun = (cfg['inbounds'] as List).first as Map;
      final settings = tun['settings'] as Map;
      // v26.7.11 源码 (infra/conf/tun.go) 只有这些键
      const allowed = {
        'name',
        'mtu',
        'gateway',
        'dns',
        'userLevel',
        'autoSystemRoutingTable',
        'autoOutboundsInterface',
      };
      expect(settings.keys.every(allowed.contains), isTrue,
          reason: 'unexpected tun keys: ${settings.keys.where((k) => !allowed.contains(k))}');
      expect(settings['autoSystemRoutingTable'], kSplitDefaultRoutes);
    });

    test('injects anti-loop direct rule for the node server IP', () {
      final cfg = buildWindowsXrayConfig(_delivered(), logPath: 'x.log');
      final rules = (cfg['routing'] as Map)['rules'] as List;
      expect(rules.first['ip'], ['203.0.113.9/32']);
      expect(rules.first['outboundTag'], 'direct');
    });

    test('does not duplicate the anti-loop rule', () {
      final cfg =
          buildWindowsXrayConfig(_delivered(withLoopRule: true), logPath: 'x.log');
      final rules = (cfg['routing'] as Map)['rules'] as List;
      final hits = rules.where((r) => (r['ip'] as List?)?.contains('203.0.113.9/32') ?? false);
      expect(hits.length, 1);
    });

    test('domain-based server gets no anti-loop rule', () {
      final cfg = buildWindowsXrayConfig(_delivered(server: 'de.example.com'), logPath: 'x.log');
      final rules = (cfg['routing'] as Map)['rules'] as List;
      expect(rules.any((r) => (r['ip'] as List?)?.any((ip) => '$ip'.endsWith('/32')) ?? false),
          isFalse);
    });

    test('keeps outbounds and enables stats/api', () {
      final cfg = buildWindowsXrayConfig(_delivered(), logPath: 'x.log');
      expect((cfg['outbounds'] as List).length, 2);
      expect(cfg['api']['services'], ['StatsService']);
      expect(cfg['policy']['system']['statsInboundUplink'], isTrue);
      expect(cfg['stats'], isEmpty);
      expect(cfg['log']['error'], 'x.log');
    });

    test('extractDnsServers returns only IP literals', () {
      final cfg = buildWindowsXrayConfig(_delivered(), logPath: 'x.log');
      expect(extractDnsServers(cfg), ['223.5.5.5']);
    });
  });
}
