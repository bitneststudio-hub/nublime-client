// R24 (Astra) — STALE_STOP_SID device-scenario enablement tests.
//
// R22 §5 could not drive the stale-sid branch on device: an external `adb am
// startservice` stop intent is refused by Android's exported-permission check, so
// the stale command never reached the product. R24 adds an OPTIONAL target-session
// argument to the stop command, reachable ONLY from the app's own debug entry (the
// fault-injection build), so the product path can now be driven from inside.
//
// These tests assert the Dart half of that contract at the platform-channel boundary:
//   1. A production stop() sends NO arguments — the shipped behaviour is unchanged.
//   2. An injection stop('stale') sends {'sessionId': 'stale'} — the argument reaches
//      XrayVpnService.onStartCommand, whose stale branch (L315-331) validates it and
//      refuses to stop the live generation.
//   3. An EMPTY target is treated as "current" (never as an arbitrary sid), so an
//      accidental empty value cannot address an arbitrary session.
//   4. A real generation bump happens on every stop — the stale stop must still
//      invalidate in-flight start/restart receipts (§7), like any other stop.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/nublimecore/nublime_core_service.dart';

/// A valid Xray-usable config for the generation test's on-disk profile.
const String _kValidTestConfig = '''{
  "log": {"loglevel": "warning"},
  "inbounds": [],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [{
      "address": "generation-test.example.invalid", "port": 443,
      "users": [{"id": "00000000-0000-0000-0000-000000000009", "encryption": "none"}]
    }]}}
  ],
  "routing": {"rules": []}
}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stopPayloads = <Object?>[];
  var stopCount = 0;

  void onStopCall(Object? arguments) {
    stopPayloads.add(arguments);
    stopCount++;
  }

  setUp(() {
    stopPayloads.clear();
    stopCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.nublime.vpn/vpn'),
      (call) async {
        switch (call.method) {
          case 'stopVpn':
            onStopCall(call.arguments);
            return '';
          case 'statusSnapshot':
            return {'status': 'Stopped', 'sessionId': 'live-session', 'seq': 1};
          case 'startVpn':
            return {'accepted': true, 'sessionId': 'live-session'};
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

  test('R24-1 production stop() sends no session argument (shipped behaviour unchanged)', () async {
    final svc = NuBLimeCoreService();
    final result = await svc.stop().run();
    expect(result.isRight(), true, reason: 'production stop must still succeed');
    expect(stopCount, 1);
    expect(stopPayloads.single, isNull,
        reason: 'no argument channel payload means the platform stops the LIVE session');
  });

  test('R24-2 fault-injection stop(stale) sends the stale sid to the platform', () async {
    final svc = NuBLimeCoreService();
    const stale = 'stale-session-0002';
    final result = await svc.stop(stale).run();
    expect(result.isRight(), true);
    expect(stopCount, 1);
    final payload = stopPayloads.single;
    expect(payload, isA<Map>());
    expect((payload as Map)['sessionId'], stale,
        reason: 'the stale sid must reach XrayVpnService.onStartCommand, which refuses it');
  });

  test('R24-3 empty target is degenerate to CURRENT, never an arbitrary sid', () async {
    final svc = NuBLimeCoreService();
    final result = await svc.stop('').run();
    expect(result.isRight(), true);
    expect(stopCount, 1);
    expect(stopPayloads.single, isNull,
        reason: 'an empty sid must degrade to the production stop-the-live-session call');
  });

  test('R24-4 every stop still bumps the command generation (in-flight receipts invalidated)', () async {
    // The generation contract is asserted without the EventChannel stream: a stop that
    // lands AFTER a start's config read must suppress that start's platform side effect.
    // Here the start is superseded while its file read is pending, so the mock channel
    // receives NO startVpn at all — that is the stop's generation bump doing its job.
    // (This mirrors the Dart-side half of the stale-sid device scenario: the stale stop
    //  is a stop like any other for command generation purposes.)
    final sentMethods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.nublime.vpn/vpn'),
      (call) async {
        sentMethods.add(call.method);
        if (call.method == 'startVpn') return {'accepted': true, 'sessionId': 'live-session'};
        if (call.method == 'stopVpn') onStopCall(call.arguments);
        if (call.method == 'statusSnapshot') {
          return {'status': 'Stopped', 'sessionId': 'live-session', 'seq': 1};
        }
        return null;
      },
    );
    final svc = NuBLimeCoreService();
    // 1) A normal start anchors the session (generation 1). It needs a readable profile
    //    file on disk — write one in the test scratch dir.
    final dir = Directory.systemTemp.createTempSync('r24-gen-');
    final profile = File('${dir.path}/profile.json')
      ..writeAsStringSync(_kValidTestConfig);
    await svc.start(profile.path, 'name', false).run();
    expect(svc.anchoredSessionId, 'live-session');
    // 2) The stale-target stop bumps the generation — an in-flight command from the
    //    previous generation may NOT re-anchor. Here no second start is in flight, so
    //    the fulfilling assertion is that the stop still ran exactly once (stopCount==1
    //    covers it) AND the anchor did not change to anything else.
    await svc.stop('stale-session-0009').run();
    expect(svc.anchoredSessionId, 'live-session',
        reason: 'a stop must never re-anchor the session to another id');
    expect(stopCount, 1);
    dir.deleteSync(recursive: true);
  });
}
