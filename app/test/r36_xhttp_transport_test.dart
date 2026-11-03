// R36/P2 — XHTTP fallback transport (converter contract).
//
// The backend can now deliver a node over either transport:
//   tcp   -> VLESS + REALITY + Vision (primary path, unchanged)
//   xhttp -> VLESS + REALITY + XHTTP (fallback when raw TCP is blocked/fingerprinted)
//
// XHTTP must never carry the Vision flow (the kernel rejects it), and a malformed or missing
// path must be rejected rather than coerced into something the kernel cannot dial.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/nublimecore/singbox_xray_converter.dart';

Map<String, dynamic> _profile({
  String? transport,
  String? xhttpPath,
  String flow = 'xtls-rprx-vision',
}) {
  final outbound = <String, dynamic>{
    'type': 'vless',
    'tag': 'nublime-vless',
    'server': 'de.example.com',
    'server_port': transport == 'xhttp' ? 8444 : 8443,
    'uuid': '11111111-2222-3333-4444-555555555555',
    'flow': flow,
    'tls': <String, dynamic>{
      'enabled': true,
      'server_name': 'www.cloudflare.com',
      'reality': <String, dynamic>{
        'enabled': true,
        'public_key': 'PUBKEYPUBKEYPUBKEYPUBKEYPUBKEYPUBKEYPUBKEY0',
        'short_id': 'deadbeef',
      },
    },
    if (transport != null) 'xray_transport': transport,
    if (xhttpPath != null) 'xray_xhttp_path': xhttpPath,
  };
  return <String, dynamic>{
    'outbounds': <dynamic>[
      outbound,
      <String, dynamic>{'type': 'selector', 'tag': 'proxy', 'outbounds': <String>['nublime-vless']},
    ],
  };
}

Map<String, dynamic> _convert(Map<String, dynamic> profile) {
  final result = SingboxXrayConverter.effectiveXrayContent(
    jsonEncode(profile),
    fingerprint: 'chrome',
  );
  return result.fold(
    (err) => throw StateError('conversion rejected: $err'),
    (out) => jsonDecode(out) as Map<String, dynamic>,
  );
}

Map<String, dynamic> _proxyOutbound(Map<String, dynamic> cfg) =>
    (cfg['outbounds'] as List).cast<Map<String, dynamic>>().firstWhere(
          (o) => o['tag'] == 'proxy',
        );

void main() {
  group('transport = tcp (unchanged primary path)', () {
    test('emits network=tcp with vision flow and no xhttpSettings', () {
      final cfg = _convert(_profile());
      final proxy = _proxyOutbound(cfg);
      final ss = proxy['streamSettings'] as Map<String, dynamic>;
      expect(ss['network'], 'tcp');
      expect(ss.containsKey('xhttpSettings'), isFalse);
      final users = ((proxy['settings'] as Map)['vnext'] as List).first['users'] as List;
      expect(users.first['flow'], 'xtls-rprx-vision');
      expect(ss['security'], 'reality');
    });

    test('legacy row without xray_transport stays tcp', () {
      final cfg = _convert(_profile());
      final ss = _proxyOutbound(cfg)['streamSettings'] as Map<String, dynamic>;
      expect(ss['network'], 'tcp');
    });
  });

  group('transport = xhttp (fallback path)', () {
    test('emits network=xhttp with the delivered path', () {
      final cfg = _convert(_profile(transport: 'xhttp', xhttpPath: '/assets/6f2c9d'));
      final proxy = _proxyOutbound(cfg);
      final ss = proxy['streamSettings'] as Map<String, dynamic>;
      expect(ss['network'], 'xhttp');
      expect(ss['xhttpSettings'], <String, dynamic>{'path': '/assets/6f2c9d', 'mode': 'auto'});
      expect(ss['security'], 'reality');
      expect((ss['realitySettings'] as Map)['serverName'], 'www.cloudflare.com');
    });

    test('drops the vision flow even when the profile still carries it', () {
      final cfg = _convert(_profile(
        transport: 'xhttp',
        xhttpPath: '/assets/6f2c9d',
        flow: 'xtls-rprx-vision',
      ));
      final users = ((_proxyOutbound(cfg)['settings'] as Map)['vnext'] as List).first['users'] as List;
      expect(users.first.containsKey('flow'), isFalse,
          reason: 'vision flow is raw-transport only; keeping it makes the kernel refuse the outbound');
    });

    test('rejects a missing path instead of guessing one', () {
      expect(
        () => _convert(_profile(transport: 'xhttp')),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a malformed path', () {
      expect(
        () => _convert(_profile(transport: 'xhttp', xhttpPath: 'assets/6f2c9d')),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects an unknown transport', () {
      expect(
        () => _convert(_profile(transport: 'quic', xhttpPath: '/x')),
        throwsA(isA<StateError>()),
      );
    });
  });
}
