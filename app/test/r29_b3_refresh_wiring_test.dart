// R29 test: R28-F1 reconnect refresh wiring + R28-F3 single-flight serialization
// (Astra R28 receipt §3.2 / §4).
//
//   R29-1  B3RefreshCoordinator single-flight: two concurrent refreshOnce calls →
//          exactly ONE backend fetch and ONE rotation (no interleaved staged writes)
//   R29-2  refreshOnce never throws: a transport failure is reported via onFailed
//   R29-3  refreshOnce reports rejections via onSkipped (non-200)
//   R29-4  STRUCTURAL wiring gate: reconnect() calls _refreshDeliveredConfig()
//          AFTER its generation guard and BEFORE _connectionRepo.reconnect();
//          _connectThrottled() likewise before _connectionRepo.connect().
//
// WHY STRUCTURAL for R29-4: a full notifier-level harness is impractical here —
// ConnectionNotifier.build() depends on activeProfileProvider (a generated
// StreamNotifier over the drift-backed profile data source), the haptic/dialog
// providers and SharedPreferences readiness (see the f5f6 note). The behavioral
// proof for the reconnect path stays with the device E2E (signing stage); this gate
// pins the call-order contract so a silent regression fails CI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:nublime/features/profile/data/profile_path_resolver.dart';
import 'package:nublime/features/profile/data/profile_repository.dart';
import 'package:nublime/features/profile/data/remote_config_refresher.dart';
import 'package:nublime/features/profile/model/profile_failure.dart';
import 'package:nublime/nublimecore/nublime_core_service.dart';

const _fakeUuid = '3c4d5e6f-3333-4444-5555-6c7d8e9f0a12';
const _fakePbk = 'r29-fixture-public-key-00000000000000';
const _fakeSid = '2c3d4e5f';

String _backendDoc({String address = 'r29-node.example.test'}) => jsonEncode({
      'log': {'level': 'info'},
      'inbounds': [
        {'type': 'tun', 'tag': 'tun-in'},
      ],
      'outbounds': [
        {
          'type': 'vless',
          'tag': 'DE-vless',
          'server': address,
          'server_port': 443,
          'uuid': _fakeUuid,
          'flow': 'xtls-rprx-vision',
          'tls': {
            'enabled': true,
            'server_name': 'r29.example.test',
            'reality': {'enabled': true, 'public_key': _fakePbk, 'short_id': _fakeSid},
          },
        },
        {'type': 'selector', 'tag': 'select', 'outbounds': ['DE-vless'], 'default': 'DE-vless'},
      ],
      'route': {'rules': <dynamic>[], 'final': 'select'},
    });

/// Hand fake: the only member the refresher uses is rotateDeliveredConfig, wired to
/// the REAL atomic rotation path (rotateDeliveredFile) so the test exercises the
/// production write semantics, and counts invocations.
class _RotatingRepo implements ProfileRepository {
  _RotatingRepo(this.resolver, this.service);
  final ProfilePathResolver resolver;
  final NuBLimeCoreService service;
  int rotations = 0;

  @override
  TaskEither<ProfileFailure, Unit> rotateDeliveredConfig(String id, String content) {
    rotations++;
    return TaskEither(() => rotateDeliveredFile(
        resolver: resolver, service: service, id: id, content: content));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'unexpected ProfileRepository member: ${invocation.memberName}');
}

/// Fake that violates the TaskEither contract on purpose — the coordinator's
/// try/catch must swallow it and report via onFailed.
class _ThrowingRepo implements ProfileRepository {
  @override
  TaskEither<ProfileFailure, Unit> rotateDeliveredConfig(String id, String content) =>
      throw StateError('boom');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'unexpected ProfileRepository member: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R29-1: single-flight — concurrent entries never interleave', () {
    late Directory tempDir;
    late ProfilePathResolver resolver;
    late NuBLimeCoreService service;
    late _RotatingRepo repo;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('r29_gate');
      resolver = ProfilePathResolver(tempDir);
      service = NuBLimeCoreService();
      repo = _RotatingRepo(resolver, service);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('two concurrent refreshOnce calls → one fetch, one rotation', () async {
      var fetches = 0;
      final coordinator = B3RefreshCoordinator(
        refresher: RemoteConfigRefresher(
          fetch: () async {
            fetches++;
            await Future<void>.delayed(const Duration(milliseconds: 80));
            return (status: 200, body: _backendDoc(address: 'r29-first.example.test'));
          },
          activeProfileId: () async => 'p-gate',
          repository: repo,
        ),
      );

      // Two entries racing (connect path + reconnect path).
      await Future.wait([
        coordinator.refreshOnce(),
        coordinator.refreshOnce(),
      ]);

      expect(fetches, 1, reason: 'the second entry must be skipped, not fetched');
      expect(repo.rotations, 1, reason: 'exactly one rotation reached the commit path');
      final rotated = jsonDecode(resolver.file('p-gate').readAsStringSync()) as Map;
      final vnext = ((((rotated['outbounds'] as List).single as Map)['settings'] as Map)['vnext'] as List).single as Map;
      expect(vnext['address'], 'r29-first.example.test',
          reason: 'the delivered artifact is one coherent rotation, never a mix');
    });
  });

  group('R29-2/R29-3: outcomes are reported, never thrown', () {
    test('transport failure → onSkipped with the fetch reason, no throw', () async {
      String? skipped;
      final tempDir = Directory.systemTemp.createTempSync('r29_t');
      final coordinator = B3RefreshCoordinator(
        refresher: RemoteConfigRefresher(
          fetch: () async => throw const SocketException('offline'),
          activeProfileId: () async => 'p',
          repository: _RotatingRepo(
              ProfilePathResolver(tempDir), NuBLimeCoreService()),
        ),
      );

      await coordinator.refreshOnce(onSkipped: (r) => skipped = r);
      tempDir.deleteSync(recursive: true);

      expect(skipped, isNotNull);
      expect(skipped, contains('offline'),
          reason: 'the refresher converts transport failures to a Left; the '
              'coordinator must surface it via onSkipped');
    });

    test('a rotation that THROWS (contract violation) → onFailed, no throw', () async {
      String? failed;
      final coordinator = B3RefreshCoordinator(
        refresher: RemoteConfigRefresher(
          fetch: () async => (status: 200, body: 'x'),
          activeProfileId: () async => 'p',
          repository: _ThrowingRepo(),
        ),
      );

      await coordinator.refreshOnce(onFailed: (r) => failed = r);

      expect(failed, isNotNull);
      expect(failed, contains('boom'));
    });

    test('non-200 → onSkipped with the status', () async {
      String? skipped;
      final tempDir = Directory.systemTemp.createTempSync('r29_s');
      final coordinator = B3RefreshCoordinator(
        refresher: RemoteConfigRefresher(
          fetch: () async => (status: 500, body: 'oops'),
          activeProfileId: () async => 'p',
          repository: _RotatingRepo(
              ProfilePathResolver(tempDir), NuBLimeCoreService()),
        ),
      );

      await coordinator.refreshOnce(onSkipped: (r) => skipped = r);
      tempDir.deleteSync(recursive: true);

      expect(skipped, isNotNull);
      expect(skipped, contains('status=500'));
    });
  });

  group('R29-4: structural wiring gate', () {
    test('reconnect refreshes between its generation guard and repo.reconnect', () {
      final src = File(
              'lib/features/connection/notifier/connection_notifier.dart')
          .readAsStringSync();

      // reconnect() body: from the method signature to the next member marker.
      final start = src.indexOf('Future<void> reconnect(');
      expect(start, greaterThan(0), reason: 'reconnect() must exist');
      final end = src.indexOf('/// F6 (Astra): monotonically increasing restart generation', start);
      expect(end, greaterThan(start), reason: 'reconnect() body boundary must be locatable');
      final body = src.substring(start, end);

      final refreshIdx = body.indexOf('await _refreshDeliveredConfig()');
      final repoReconnectIdx = body.indexOf('_connectionRepo.reconnect(');
      expect(refreshIdx, greaterThan(0),
          reason: 'R28-F1: reconnect() must call await _refreshDeliveredConfig()');
      expect(repoReconnectIdx, greaterThan(refreshIdx),
          reason: 'the refresh must land BEFORE repo.reconnect()');
      expect(
        body.indexOf('generationAtIssue != _restartGeneration', refreshIdx),
        greaterThan(refreshIdx),
        reason: 'F6: a generation re-check must follow the refresh (async boundary)',
      );
    });

    test('connect path refreshes before repo.connect', () {
      final src = File(
              'lib/features/connection/notifier/connection_notifier.dart')
          .readAsStringSync();
      final start = src.indexOf('Future<void> _connectThrottled(');
      expect(start, greaterThan(0));
      final end = src.indexOf('/// R28-F1/F3 (Astra): single-flight refresh', start);
      expect(end, greaterThan(start),
          reason: '_connectThrottled() body boundary must be locatable');
      final body = src.substring(start, end);

      final refreshIdx = body.indexOf('_refreshDeliveredConfig()');
      final repoConnectIdx = body.indexOf('await _connectionRepo.connect(');
      expect(refreshIdx, greaterThan(0),
          reason: 'the connect path must keep its B-3 refresh');
      expect(repoConnectIdx, greaterThan(refreshIdx),
          reason: 'the refresh must land BEFORE repo.connect()');
    });
  });
}
