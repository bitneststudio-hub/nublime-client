// R02 (Astra) — REAL core-service consumption tests.
//
// Executes the REAL NuBLimeCoreService.start/restart against a FAKE MethodChannel and
// observes the payload at the platform-channel boundary (Astra §3.4.4: only fake the
// channel, never the code under test).
//
// Negative control (Astra §3.4.6): the profile content used here is deliberately
// DIFFERENT from the built-in single-node config. Restoring the `_defaultXrayConfig`
// fallback anywhere in the delivery chain makes R02-1/R02-2/R02-5 fail, because the
// channel would then receive the builtin config instead of the delivered file content.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/nublimecore/nublime_core_service.dart';

/// A valid Xray-usable config, deliberately DIFFERENT from `_defaultXrayConfig`
/// (different node, different loglevel, an extra direct outbound, no Reality block).
const String _testConfigA = '''{
  "log": {"loglevel": "warning"},
  "inbounds": [],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [{
      "address": "test-node-a.example.invalid", "port": 443,
      "users": [{"id": "00000000-0000-0000-0000-000000000001", "encryption": "none"}]
    }]}},
    {"tag": "direct", "protocol": "freedom"}
  ],
  "routing": {"rules": []}
}''';

const String _testConfigB = '''{
  "log": {"loglevel": "error"},
  "inbounds": [],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [{
      "address": "test-node-b.example.invalid", "port": 8443,
      "users": [{"id": "00000000-0000-0000-0000-000000000002", "encryption": "none"}]
    }]}}
  ],
  "routing": {"rules": []}
}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sentStartConfigs = <String>[];
  final callOrder = <String>[];
  var stopCalls = 0;

  setUp(() {
    sentStartConfigs.clear();
    callOrder.clear();
    stopCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.nublime.vpn/vpn'),
      (call) async {
        callOrder.add(call.method);
        switch (call.method) {
          case 'startVpn':
            sentStartConfigs.add((call.arguments! as Map)['config']! as String);
            return {'accepted': true, 'sessionId': 'test-session-0001'};
          case 'stopVpn':
            stopCalls++;
            return '';
          case 'statusSnapshot':
            return {'status': 'Started', 'sessionId': 'test-session-0001', 'seq': 1};
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.nublime.vpn/vpn'),
      null,
    );
  });

  Future<(Directory, NuBLimeCoreService)> fresh() async {
    final dir = await Directory.systemTemp.createTemp('r02_real_core_');
    return (dir, NuBLimeCoreService());
  }

  test('R02-1 start() sends the DELIVERED file content (never a built-in fallback)', () async {
    final (dir, service) = await fresh();
    addTearDown(() => dir.deleteSync(recursive: true));
    final profile = File('${dir.path}/profile-a.json');
    await profile.writeAsString(_testConfigA);

    final result = await service.start(profile.path, 'test-profile', false).run();

    expect(result.isRight(), isTrue, reason: 'start must succeed on a valid delivered config');
    // The channel received EXACTLY the file content — the negative control: any restored
    // `_defaultXrayConfig` fallback would deliver the builtin instead and fail this check.
    expect(sentStartConfigs, hasLength(1));
    expect(sentStartConfigs.single, _testConfigA);
    expect(sentStartConfigs.single, isNot(NuBLimeCoreService.r02NegativeControlBuiltin));
    expect(service.anchoredSessionId, 'test-session-0001');
  });

  test('R02-2 restart() reads the file at restart time and sends the ROTATED content', () async {
    final (dir, service) = await fresh();
    addTearDown(() => dir.deleteSync(recursive: true));
    final profile = File('${dir.path}/profile-a.json');
    await profile.writeAsString(_testConfigA);

    final first = await service.restart(profile.path, 'test-profile', false).run();
    expect(first.isRight(), isTrue);
    // refreshSnapshot appends a trailing 'statusSnapshot'; the COMMAND order is what R02 checks.
    expect(callOrder.take(2), ['stopVpn', 'startVpn'], reason: 'restart stops first, then starts');
    expect(sentStartConfigs.single, _testConfigA);

    // Rotate the delivered profile, then restart again: the restart must re-read the file
    // and send the NEW content (the builtin fallback can never produce this).
    callOrder.clear();
    sentStartConfigs.clear();
    await profile.writeAsString(_testConfigB);

    final second = await service.restart(profile.path, 'test-profile', false).run();
    expect(second.isRight(), isTrue);
    expect(callOrder.take(2), ['stopVpn', 'startVpn']);
    expect(stopCalls, 2, reason: 'both restarts issue exactly one stop each');
    expect(sentStartConfigs.single, _testConfigB,
        reason: 'restart must consume the rotated file content');
    expect(sentStartConfigs.single, isNot(NuBLimeCoreService.r02NegativeControlBuiltin));
  });

  test('R02-3 missing profile file fails explicitly with NO channel call', () async {
    final (dir, service) = await fresh();
    addTearDown(() => dir.deleteSync(recursive: true));
    final missing = File('${dir.path}/never-delivered.json');

    final result = await service.start(missing.path, 'test-profile', false).run();

    expect(result.isLeft(), isTrue);
    result.fold(
      (l) => expect(l.toString(), contains('not found')),
      (_) => fail('start must fail on a missing profile'),
    );
    expect(callOrder, isEmpty, reason: 'no channel call may happen for an unreadable profile');
    expect(sentStartConfigs, isEmpty);
  });

  test('R02-4 empty / non-JSON / no-outbounds profiles fail explicitly', () async {
    final (dir, service) = await fresh();
    addTearDown(() => dir.deleteSync(recursive: true));

    // empty content
    final empty = File('${dir.path}/empty.json');
    await empty.writeAsString('   \n');
    var r = await service.start(empty.path, 'p', false).run();
    expect(r.isLeft(), isTrue);
    expect(callOrder, isEmpty);

    // raw subscription content (URI lines) is NOT an Xray config
    callOrder.clear();
    final rawSub = File('${dir.path}/raw.json');
    await rawSub.writeAsString('vless://00000000-0000-0000-0000-000000000003@example.invalid:443\n');
    r = await service.start(rawSub.path, 'p', false).run();
    expect(r.isLeft(), isTrue);
    r.fold(
      (l) => expect(l.toString(), contains('not valid JSON')),
      (_) => fail('raw subscription content must fail explicitly'),
    );
    expect(callOrder, isEmpty);

    // JSON but no outbounds
    callOrder.clear();
    final noOutbounds = File('${dir.path}/no-outbounds.json');
    await noOutbounds.writeAsString('{"log": {"loglevel": "warning"}, "inbounds": []}');
    r = await service.start(noOutbounds.path, 'p', false).run();
    expect(r.isLeft(), isTrue);
    r.fold(
      (l) => expect(l.toString(), contains('outbounds')),
      (_) => fail('a config without outbounds must fail explicitly'),
    );
    expect(callOrder, isEmpty, reason: 'nothing may reach the native core from an invalid profile');
  });

  test('R02-5 negative control: the builtin single-node config is never what the channel receives',
      () async {
    final (dir, service) = await fresh();
    addTearDown(() => dir.deleteSync(recursive: true));
    final profile = File('${dir.path}/profile-a.json');
    await profile.writeAsString(_testConfigA);

    await service.start(profile.path, 'p', false).run();
    callOrder.clear();
    sentStartConfigs.clear();
    await profile.writeAsString(_testConfigB);
    await service.restart(profile.path, 'p', false).run();

    for (final sent in sentStartConfigs) {
      expect(sent, isNot(NuBLimeCoreService.r02NegativeControlBuiltin),
          reason: 'the builtin fallback must never be sent — restoring it fails this test');
    }
    expect(sentStartConfigs, contains(_testConfigB));
  });
}
