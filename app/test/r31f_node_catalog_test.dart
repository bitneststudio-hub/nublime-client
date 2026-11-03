// B-3 client data layer: catalog parsing, endpoint shape, pick persistence.
import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/features/profile/data/node_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseServers', () {
    test('N1: parses the backend payload (id/country/host/port/flag/recommended)', () {
      const body = '''
      [{"id":"eca3027b-f596-47f0-898c-4d58471a5765","country":"德国","countryCode":"DE",
        "city":"德国","flag":"🇩🇪","host":"198.51.100.7","port":8443,
        "protocol":"VLESS_REALITY","load":0,"isRecommended":true},
       {"id":"11111111-2222-3333-4444-555555555555","country":"日本","countryCode":"JP",
        "flag":"🇯🇵","host":"198.51.100.7","port":9444,
        "protocol":"VLESS_REALITY","load":12,"isRecommended":false}]''';
      final nodes = parseServers(body);
      expect(nodes.length, 2);
      expect(nodes.first.id, 'eca3027b-f596-47f0-898c-4d58471a5765');
      expect(nodes.first.port, 8443);
      expect(nodes.first.isRecommended, isTrue);
      expect(nodes.last.country, '日本');
      expect(nodes.last.port, 9444);
    });

    test('N2: entries without an id are dropped (cannot be selected)', () {
      final nodes = parseServers('[{"country":"X"},{"id":"  ","country":"Y"},{"id":"ok"}]');
      expect(nodes.map((n) => n.id).toList(), ['ok']);
    });

    test('N3: malformed payload throws instead of silently emptying the picker', () {
      expect(() => parseServers('not json'), throwsA(isA<FormatException>()));
      expect(() => parseServers('{"a":1}'), throwsA(isA<FormatException>()));
    });

    test('N4: empty list is a valid answer (no nodes), not an error', () {
      expect(parseServers('[]'), isEmpty);
    });

    test('N5: numeric strings are tolerated, junk becomes 0', () {
      final nodes = parseServers('[{"id":"a","port":"9444","load":"7"},{"id":"b","port":"x"}]');
      expect(nodes.first.port, 9444);
      expect(nodes.first.load, 7);
      expect(nodes.last.port, 0);
    });
  });

  group('nodeConfigEndpoint', () {
    test('N6: no pick -> backend default', () {
      expect(nodeConfigEndpoint(), kNodeConfigEndpoint);
      expect(nodeConfigEndpoint(serverId: '   '), kNodeConfigEndpoint);
    });

    test('N7: a pick -> server_id query, url-encoded', () {
      expect(nodeConfigEndpoint(serverId: 'abc-123'),
          'https://www.nublime.com/api/app/config/singbox?server_id=abc-123');
      // encodeQueryComponent follows form-urlencoding: space -> '+', '&' -> %26.
      // Real ids are UUIDs, so this only guards against a malformed pick breaking the URL.
      expect(nodeConfigEndpoint(serverId: 'a b&c'),
          'https://www.nublime.com/api/app/config/singbox?server_id=a+b%26c');
    });
  });

  group('SelectedNodeStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('N8: write/read round-trip, trims whitespace', () async {
      final store = SelectedNodeStore();
      expect(await store.read(), isNull);
      await store.write('  node-1  ');
      expect(await store.read(), 'node-1');
    });

    test('N9: reconcile clears a pick whose node disappeared', () async {
      final store = SelectedNodeStore();
      await store.write('gone');
      final nodes = parseServers('[{"id":"present","country":"X"}]');
      expect(await store.reconcile(nodes), isNull);
      expect(await store.read(), isNull);
    });

    test('N10: reconcile keeps a still-existing pick', () async {
      final store = SelectedNodeStore();
      await store.write('present');
      final nodes = parseServers('[{"id":"present","country":"X"}]');
      expect(await store.reconcile(nodes), 'present');
    });
  });
}
