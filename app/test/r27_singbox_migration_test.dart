// R2-6 regression test: migration of legacy sing-box profiles to the Xray wire shape.
//
// The production activation backend (04_服务端部署_脱敏/历史_已废弃/app.routes.js,
// generateSingboxConfig) delivers node profiles in sing-box format, and the pre-rebuild
// app stored exactly that shape in configs/<id>.json. The Xray core and its schema
// validator (R02, Astra 10-09 §4.2) accept only the Xray wire shape. R2-6 closes the
// format gap with ONE converter (SingboxXrayConverter) wired into every delivery-chain
// site. This suite pins:
//
//   R27-1  the REAL backend document shape converts to a valid Xray config
//          (single=true: one vless + one hysteria2 + one selector; hy2 is dropped)
//   R27-2  missing `flow` defaults to xtls-rprx-vision
//   R27-3  Xray-shaped content passes through UNCHANGED (byte-identical)
//   R27-4  conversion is idempotent (converted output re-converts as a no-op)
//   R27-5  node selection honors route.final → selector → default (multi-node doc)
//   R27-6  route.final may name the vless outbound directly (no selector hop)
//   R27-7  fail-closed matrix: every missing critical field rejects the whole
//          conversion with an explicit reason — no partial config ever emitted
//   R27-8  read path: generateFullConfigByPath returns Xray content for a legacy file
//          AND leaves the stored file byte-identical (lazy migration, no rewrite)
//   R27-9  commit path: validateConfigByPath persists the CONVERTED artifact and
//          consumes the staged input (R18.1 §7.2 semantics preserved)
//   R27-10 read-path regression: Xray-shaped files still read/validate unchanged
//
// All fixture credentials are sanitized by construction (RFC 2606 .test domains,
// 203.0.113.x IPs, dummy uuid/keys) — no production values appear here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:nublime/nublimecore/nublime_core_service.dart';
import 'package:nublime/nublimecore/singbox_xray_converter.dart';

const tUuid = '1a2b3c4d-1111-2222-3333-4a5b6c7d8e9f';
// 43 chars — same length class as a real Reality public key, dummy content.
const tPbk = 'test-public-key-0000000000000000000000000';
const tSid = '0a1b2c3d';
const tServer = 'de-node.example.test';
const tSni = 'www.example.test';
const tFingerprint = 'chrome';

/// The production renderer's single=true document (generateSingboxConfig), sanitized.
Map<String, dynamic> backendSingboxDoc({
  String selectorDefault = 'DE-vless',
  String routeFinal = 'select',
  List<Map<String, dynamic>>? outboundsOverride,
}) {
  final deVless = <String, dynamic>{
    'type': 'vless',
    'tag': 'DE-vless',
    'server': tServer,
    'server_port': 443,
    'uuid': tUuid,
    'flow': 'xtls-rprx-vision',
    'tls': {
      'enabled': true,
      'server_name': tSni,
      'reality': {'enabled': true, 'public_key': tPbk, 'short_id': tSid},
    },
  };
  final hy2 = <String, dynamic>{
    'type': 'hysteria2',
    'tag': 'DE-hy2',
    'server': tServer,
    'server_port': 443,
    'password': 'not-a-real-secret',
    'tls': {'enabled': true, 'server_name': tSni},
  };
  final selector = <String, dynamic>{
    'type': 'selector',
    'tag': 'select',
    'outbounds': ['DE-vless', 'DE-hy2'],
    'default': selectorDefault,
  };
  return <String, dynamic>{
    'log': {'level': 'info'},
    'dns': {
      'servers': [
        {'tag': 'cloudflare', 'address': 'https://1.1.1.1/dns-query', 'detour': 'direct'},
        {'tag': 'local', 'address': '223.5.5.5', 'detour': 'direct'},
      ],
      'rules': [
        {'geosite': 'cn', 'server': 'local'},
      ],
      'final': 'cloudflare',
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'address': ['172.19.0.1/30'],
        'auto_route': true,
        'strict_route': true,
        'stack': 'mixed',
      },
    ],
    'outbounds': outboundsOverride ?? [deVless, hy2, selector],
    'route': {
      'rules': [
        {'ip_cidr': ['203.0.113.10/32'], 'outbound': 'direct'},
        {'geosite': 'cn', 'outbound': 'direct'},
      ],
      'final': routeFinal,
    },
  };
}

/// An Xray-shaped document (the built-in template family) for passthrough cases.
const xrayShapedDoc = '''
{
  "log":{"loglevel":"debug"},
  "inbounds":[],
  "outbounds":[{
    "tag":"proxy",
    "protocol":"vless","settings":{"vnext":[{
      "address":"de-node.example.test","port":443,
      "users":[{"id":"$tUuid","encryption":"none","flow":"xtls-rprx-vision"}]
    }]},
    "streamSettings":{"network":"tcp","security":"reality","realitySettings":{
      "serverName":"$tSni","publicKey":"$tPbk",
      "shortId":"$tSid","fingerprint":"$tFingerprint"
    }}
  }],
  "routing":{"domainStrategy":"AsIs","rules":[{"type":"field","inboundTag":["socks-in"],"network":"tcp,udp","outboundTag":"proxy"}]}
}''';

String expectRight(XrayContentResult r) => r.fold(
    (l) => fail('conversion rejected a document it must accept: $l'), (c) => c);

String expectLeft(XrayContentResult r) => r.fold(
    (l) => l, (c) => fail('conversion accepted a document it must reject'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R27-1: backend single=true document → Xray config', () {
    test('converts; hy2 dropped; passes the ONE validator', () {
      final res = SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(backendSingboxDoc()),
          fingerprint: tFingerprint);

      final out = expectRight(res);
      final decoded = jsonDecode(out) as Map<String, dynamic>;

      final outbounds = decoded['outbounds'] as List;
      expect(outbounds, hasLength(1), reason: 'hysteria2 must be dropped, not emitted');

      final ob = outbounds.single as Map<String, dynamic>;
      expect(ob['tag'], 'proxy');
      expect(ob['protocol'], 'vless');
      final vnext = (ob['settings'] as Map)['vnext'] as List;
      expect((vnext.single as Map)['address'], tServer);
      expect((vnext.single as Map)['port'], 443);
      final user = ((vnext.single as Map)['users'] as List).single as Map;
      expect(user['id'], tUuid);
      expect(user['encryption'], 'none');
      expect(user['flow'], 'xtls-rprx-vision');
      final ss = ob['streamSettings'] as Map;
      expect(ss['network'], 'tcp');
      expect(ss['security'], 'reality');
      final rs = ss['realitySettings'] as Map;
      expect(rs['serverName'], tSni);
      expect(rs['publicKey'], tPbk);
      expect(rs['shortId'], tSid);
      expect(rs['fingerprint'], tFingerprint);

      // socks-in → proxy is the routing the hev feeding path relies on.
      final rule = ((decoded['routing'] as Map)['rules'] as List).single as Map;
      expect(rule['inboundTag'], ['socks-in']);
      expect(rule['outboundTag'], 'proxy');

      // Integration with the ONE validator: the emitted doc must be schema-valid.
      expect(
        NuBLimeCoreService.validateXrayConfigContent(out).isRight(),
        true,
        reason: 'converted document must satisfy validateXrayConfigContent',
      );
    });
  });

  group('R27-2: flow default', () {
    test('missing flow defaults to xtls-rprx-vision', () {
      final doc = backendSingboxDoc();
      (doc['outbounds'] as List).first.remove('flow');
      final out = expectRight(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      final vnext = (((((jsonDecode(out) as Map)['outbounds'] as List).single
              as Map)['settings'] as Map)['vnext'] as List);
      expect(((vnext.single as Map)['users'] as List).single,
          containsPair('flow', 'xtls-rprx-vision'));
    });
  });

  group('R27-3: Xray-shaped content passes through unchanged', () {
    test('byte-identical passthrough', () {
      final res = SingboxXrayConverter.effectiveXrayContent(xrayShapedDoc,
          fingerprint: tFingerprint);
      expect(expectRight(res), xrayShapedDoc);
    });
  });

  group('R27-4: idempotence', () {
    test('converted output re-converts as a no-op', () {
      final first = expectRight(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(backendSingboxDoc()), fingerprint: tFingerprint));
      final second = expectRight(SingboxXrayConverter.effectiveXrayContent(
          first, fingerprint: tFingerprint));
      expect(second, first);
    });
  });

  group('R27-5: selector default honored (multi-node document)', () {
    test('selector default names the NL node → NL is dialed', () {
      final nlVless = <String, dynamic>{
        'type': 'vless',
        'tag': 'NL-vless',
        'server': 'nl-node.example.test',
        'server_port': 8443,
        'uuid': tUuid,
        'flow': 'xtls-rprx-vision',
        'tls': {
          'enabled': true,
          'server_name': 'nl.example.test',
          'reality': {'enabled': true, 'public_key': tPbk, 'short_id': tSid},
        },
      };
      final doc = backendSingboxDoc(
        selectorDefault: 'NL-vless',
        outboundsOverride: [
          (backendSingboxDoc()['outbounds'] as List).first as Map<String, dynamic>,
          nlVless,
          <String, dynamic>{
            'type': 'selector',
            'tag': 'select',
            'outbounds': ['DE-vless', 'NL-vless'],
            'default': 'NL-vless',
          },
        ],
      );
      final out = expectRight(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      final vnext =
          (((decoded['outbounds'] as List).single as Map)['settings'] as Map)['vnext'] as List;
      expect((vnext.single as Map)['address'], 'nl-node.example.test');
      expect((vnext.single as Map)['port'], 8443);
      expect(
        NuBLimeCoreService.validateXrayConfigContent(out).isRight(),
        true,
      );
    });
  });

  group('R27-6: route.final names the vless outbound directly', () {
    test('no selector hop — the named node is dialed', () {
      final doc = backendSingboxDoc(routeFinal: 'DE-vless');
      final out = expectRight(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      final vnext =
          (((decoded['outbounds'] as List).single as Map)['settings'] as Map)['vnext'] as List;
      expect((vnext.single as Map)['address'], tServer);
    });
  });

  group('R27-7: fail-closed matrix', () {
    test('missing uuid → explicit rejection', () {
      final doc = backendSingboxDoc();
      (doc['outbounds'] as List).first.remove('uuid');
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      expect(reason, contains('uuid'));
    });

    test('port 0 → explicit rejection', () {
      final doc = backendSingboxDoc();
      (doc['outbounds'] as List).first['server_port'] = 0;
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      expect(reason, contains('server_port'));
    });

    test('port 70000 → explicit rejection', () {
      final doc = backendSingboxDoc();
      (doc['outbounds'] as List).first['server_port'] = 70000;
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      expect(reason, contains('server_port'));
    });

    test('missing reality public_key → explicit rejection', () {
      final doc = backendSingboxDoc();
      final tls = ((doc['outbounds'] as List).first as Map)['tls'] as Map;
      (tls['reality'] as Map).remove('public_key');
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      expect(reason, contains('public_key'));
    });

    test('tls.enabled=false → explicit rejection', () {
      final doc = backendSingboxDoc();
      ((doc['outbounds'] as List).first as Map)['tls'] = {
        'enabled': false,
        'server_name': tSni,
        'reality': {'enabled': true, 'public_key': tPbk, 'short_id': tSid},
      };
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      expect(reason, contains('tls.enabled'));
    });

    test('reality.enabled=false → explicit rejection', () {
      final doc = backendSingboxDoc();
      final tls = ((doc['outbounds'] as List).first as Map)['tls'] as Map;
      tls['reality'] = {'enabled': false, 'public_key': tPbk, 'short_id': tSid};
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      expect(reason, contains('reality.enabled'));
    });

    test('hysteria2-only document → explicit rejection (never dialed, never guessed)', () {
      final doc = backendSingboxDoc(
        selectorDefault: 'DE-hy2',
        outboundsOverride: [
          (backendSingboxDoc()['outbounds'] as List)[1] as Map<String, dynamic>, // hy2
          <String, dynamic>{
            'type': 'selector',
            'tag': 'select',
            'outbounds': ['DE-hy2'],
            'default': 'DE-hy2',
          },
        ],
      );
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      expect(reason, contains('not a vless node'));
    });

    test('route.final references a missing tag → refuses to guess', () {
      final doc = backendSingboxDoc(routeFinal: 'no-such-tag');
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      expect(reason, contains('missing outbound'));
    });

    test('invalid JSON → explicit rejection', () {
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          '{not json', fingerprint: tFingerprint));
      expect(reason, contains('not valid JSON'));
    });

    test('JSON array (not an object) → explicit rejection', () {
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          '[1,2,3]', fingerprint: tFingerprint));
      expect(reason, contains('not a config JSON object'));
    });

    test('empty outbounds has no legacy marker → converter passes through, validator rejects',
        () {
      // Layering (by design): the converter is a FORMAT bridge — an empty outbounds
      // list carries no `type` marker, so it is not sing-box-shaped and passes through
      // untouched. Schema enforcement is the validator's job (R02, ONE validator);
      // asserting that split here pins both halves of the contract.
      final doc = backendSingboxDoc();
      doc['outbounds'] = <dynamic>[];
      final encoded = jsonEncode(doc);
      final passedThrough = expectRight(SingboxXrayConverter.effectiveXrayContent(
          encoded, fingerprint: tFingerprint));
      expect(passedThrough, encoded,
          reason: 'no legacy marker → byte-identical passthrough');
      expect(
        NuBLimeCoreService.validateXrayConfigContent(passedThrough).isLeft(),
        true,
        reason: 'the ONE validator must reject an empty outbounds list',
      );
    });
  });

  group('R27-8 / R27-9 / R27-10: delivery-chain integration', () {
    late Directory tempDir;
    late NuBLimeCoreService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('r27_singbox_migration');
      service = NuBLimeCoreService();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('R27-8: read path returns Xray content AND leaves the legacy file untouched',
        () async {
      final legacy = File('${tempDir.path}/legacy.json')
        ..writeAsStringSync(jsonEncode(backendSingboxDoc()));
      final original = legacy.readAsStringSync();

      final outcome =
          await service.generateFullConfigByPath(legacy.path).run();

      outcome.fold(
        (l) => fail('read path rejected the legacy profile: $l'),
        (content) {
          final decoded = jsonDecode(content) as Map<String, dynamic>;
          expect(
            ((decoded['outbounds'] as List).single as Map)['protocol'],
            'vless',
            reason: 'the read path must hand out Xray-shaped content',
          );
          expect(
            NuBLimeCoreService.validateXrayConfigContent(content).isRight(),
            true,
          );
          expect(
            legacy.readAsStringSync(),
            original,
            reason: 'lazy migration must NEVER rewrite the stored profile file',
          );
        },
      );
    });

    test('R27-9: commit path persists the CONVERTED artifact and consumes the staged input',
        () async {
      final stagedFile = File('${tempDir.path}/staged.json')
        ..writeAsStringSync(jsonEncode(backendSingboxDoc()));
      final target = File('${tempDir.path}/configs/p1.json')
        ..createSync(recursive: true);

      final outcome = await service
          .validateConfigByPath(target.path, stagedFile.path, false)
          .run();

      expect(outcome.isRight(), true,
          reason: 'commit path must accept a legacy sing-box delivery');
      final committed = jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;
      expect(
        ((committed['outbounds'] as List).single as Map)['protocol'],
        'vless',
        reason: 'the persisted artifact must be the CONVERTED Xray document',
      );
      expect(
        NuBLimeCoreService.validateXrayConfigContent(target.readAsStringSync()).isRight(),
        true,
      );
      expect(stagedFile.existsSync(), false,
          reason: 'R18.1 §7.2: the staged input is consumed on a published commit');
    });

    test('R27-9b: commit path rejects a broken legacy delivery without touching the target',
        () async {
      final broken = backendSingboxDoc();
      (broken['outbounds'] as List).first.remove('uuid');
      final stagedFile = File('${tempDir.path}/staged-broken.json')
        ..writeAsStringSync(jsonEncode(broken));
      final target = File('${tempDir.path}/configs/p2.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(xrayShapedDoc);

      final outcome = await service
          .validateConfigByPath(target.path, stagedFile.path, false)
          .run();

      expect(outcome.isLeft(), true,
          reason: 'a broken legacy delivery must fail the commit');
      expect(
        target.readAsStringSync(),
        xrayShapedDoc,
        reason: 'the previous valid profile must be preserved on a failed commit',
      );
      expect(stagedFile.existsSync(), true,
          reason: 'a failed commit must not consume the staged input');
    });

    test('R27-10: Xray-shaped files still read/validate unchanged (regression)',
        () async {
      final xrayFile = File('${tempDir.path}/xray.json')
        ..writeAsStringSync(xrayShapedDoc);
      final outcome =
          await service.generateFullConfigByPath(xrayFile.path).run();
      outcome.fold(
        (l) => fail('read path regressed on Xray-shaped content: $l'),
        (content) => expect(content, xrayShapedDoc),
      );
    });
  });

  // ---------------------------------------------------------------------------------
  // R27-F2 (Astra R27 receipt, closed with B-3): a PRESENT-but-malformed route is
  // rejected explicitly — never silently scanned. `route.final` stays OPTIONAL per the
  // sing-box spec, so a well-formed route object without `final` still scans.
  // ---------------------------------------------------------------------------------
  group('R27-F2: malformed route structure', () {
    test('route present but not an object → explicit rejection', () {
      final doc = backendSingboxDoc();
      doc['route'] = 'select';
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      expect(reason, contains('route must be an object'));
    });

    test('route.final present but not a string tag → explicit rejection', () {
      final doc = backendSingboxDoc();
      (doc['route'] as Map<String, dynamic>)['final'] = 123;
      final reason = expectLeft(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      expect(reason, contains('route.final must be a string'));
    });

    test('route object without final → documented deterministic scan', () {
      final doc = backendSingboxDoc();
      (doc['route'] as Map<String, dynamic>).remove('final');
      final out = expectRight(SingboxXrayConverter.effectiveXrayContent(
          jsonEncode(doc), fingerprint: tFingerprint));
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      final vnext =
          (((decoded['outbounds'] as List).single as Map)['settings'] as Map)['vnext'] as List;
      expect((vnext.single as Map)['address'], tServer);
      expect(NuBLimeCoreService.validateXrayConfigContent(out).isRight(), true);
    });
  });
}
