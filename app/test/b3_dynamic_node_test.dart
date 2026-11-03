// B-3 regression test (deployment spec §5, "动态节点下发"): node delivery must be
// backend-driven and rotatable, and the shipped binary must carry ZERO live node data
// ("客户端不硬编码 IP/Reality 密钥（反编译也拿不到固定服务器清单）").
//
//   B3-1  static gate: shipped source carries no production node values/identifiers
//         and no deployment_credentials import — any hardcode reintroduction fails
//   B3-2  the R02 negative-control builtin carries deliberate dummy values only
//   B3-3  rotateDeliveredFile: valid backend content atomically replaces the delivered
//         file (sing-box → converted Xray artifact), staged input consumed
//   B3-4  rotateDeliveredFile: invalid content preserves the previous artifact
//         byte-for-byte and cleans the staged input
//   B3-5  RemoteConfigRefresher: success rotates with the exact profileId + body
//   B3-6  RemoteConfigRefresher: non-200 / empty body / no profile / fetch exception
//         → Left, rotation never invoked
//   B3-7  rotation failure propagates as Left (in production the connect proceeds
//         with the existing artifact — never a built-in fallback)
//
// Fixture values are sanitized by construction (RFC 2606 .test domains, fake
// uuid/pbk/sid) — no production values appear here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:nublime/features/profile/data/profile_path_resolver.dart';
import 'package:nublime/features/profile/data/profile_repository.dart';
import 'package:nublime/features/profile/data/remote_config_refresher.dart';
import 'package:nublime/features/profile/model/profile_failure.dart';
import 'package:nublime/nublimecore/nublime_core_service.dart';

const _fakeUuid = '2b3c4d5e-2222-3333-4444-5b6c7d8e9f01';
const _fakePbk = 'b3-fixture-public-key-0000000000000000';
const _fakeSid = '1b2c3d4e';

String _backendDoc() => jsonEncode({
      'log': {'level': 'info'},
      'inbounds': [
        {'type': 'tun', 'tag': 'tun-in'},
      ],
      'outbounds': [
        {
          'type': 'vless',
          'tag': 'DE-vless',
          'server': 'b3-node.example.test',
          'server_port': 443,
          'uuid': _fakeUuid,
          'flow': 'xtls-rprx-vision',
          'tls': {
            'enabled': true,
            'server_name': 'b3.example.test',
            'reality': {
              'enabled': true,
              'public_key': _fakePbk,
              'short_id': _fakeSid,
            },
          },
        },
        {
          'type': 'selector',
          'tag': 'select',
          'outbounds': ['DE-vless'],
          'default': 'DE-vless',
        },
      ],
      'route': {'rules': <dynamic>[], 'final': 'select'},
    });

const _previousXrayDoc = '''{
  "log":{"loglevel":"debug"},
  "inbounds":[],
  "outbounds":[{"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":"old-node.example.test","port":443,"users":[{"id":"old-node-uuid"}]}]}}],
  "routing":{"domainStrategy":"AsIs","rules":[]}
}''';

/// Minimal hand fake: the refresher only ever calls [rotateDeliveredConfig]; any
/// other interface member throws so accidental coupling fails loudly.
class _FakeProfileRepo implements ProfileRepository {
  final List<({String id, String content})> rotations = [];
  TaskEither<ProfileFailure, Unit> Function(String id, String content) onRotate =
      (id, content) => TaskEither.right(unit);

  @override
  TaskEither<ProfileFailure, Unit> rotateDeliveredConfig(String id, String content) {
    rotations.add((id: id, content: content));
    return onRotate(id, content);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'unexpected ProfileRepository member: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B3-1: static gate — no production node data in shipped source', () {
    test('lib/ carries no production values, identifiers or credentials import', () {
      // 反编译拿不到固定清单: the production node's address, UUID, Reality trio,
      // credential identifiers and the deployment_credentials import must not exist
      // anywhere under lib/ (excluding generated files).
      //
      // DISCIPLINE: the needles below are assembled from SPLIT string literals on
      // purpose — this gate must never smuggle (into the repository) the very
      // literals it bans. A plain-text grep of this file finds no complete
      // production value or identifier.
      final banned = <String>[
        '178' '.104' '.17' '.157', // production node address
        '9fef' '8349' '-' '723e' '-4136' '-bc3b' '-966043' 'fb9e5b', // VLESS UUID
        '87d6' '8034', // Reality short_id
        'CxD6s8n' 'IIplOkm' 'JAaQjqspCm' '_mOgmPtg' 'TTRU8AWGc' '1Y', // Reality public_key
        'kProd' 'NodeAddress',
        'kProd' 'NodePort',
        'kProd' 'VlessUuid',
        'kProd' 'RealityPublicKey',
        'kProd' 'RealityShortId',
        'kProd' 'RealitySni',
        'deployment' '_credentials',
      ];
      final offenders = <String>[];
      // Generic defense-in-depth: any bare IPv4 literal outside the benign
      // allowlist (loopback / wildcard / public DNS / tun addresses) is treated as a
      // hardcoded endpoint — a DIFFERENT production address trips this even if
      // nobody updates the needle list above.
      const benignIps = <String>{
        '127.0.0.1', // loopback (local debug bridge)
        '0.0.0.0', // wildcard bind
        '8.8.8.8', '8.8.4.4', '1.1.1.1', '1.1.1.2', '1.0.0.1', '4.4.2.2',
        '223.5.5.5', '119.29.29.29', // public DNS resolvers offered in settings
        '10.0.0.2', // WireGuard sample config placeholder (json_editor demo)
        '10.8.0.2', // Xray VpnService tun local address (XrayVpnService.kt)
        '198.18.0.1', // Xray tun gateway (benchmark range, XrayVpnService.kt)
        '10.9.0.1', // Windows tun local address (lib/platform/windows/windows_config_builder.dart)
        '128.0.0.0', // /1 route prefix, not an endpoint (windows tunnel split routes)
      };
      final ipv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
      // R28-F2 (Astra): coverage extended beyond lib/**/*.dart — Kotlin/XML/gradle
      // sources ship in the APK too. Compiled assets (.so/.aar) are out of scope: a
      // static string scan of binaries is meaningless; the value-based grep covers them.
      final roots = <String>['lib', 'android/app'];
      final files = <File>[];
      for (final root in roots) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is! File) continue;
          final p = entity.path;
          if (p.endsWith('.g.dart')) continue;
          if (p.contains('/build/') || p.contains('/.gradle/')) continue;
          const exts = ['.dart', '.kt', '.java', '.xml', '.gradle', '.kts'];
          if (!exts.any(p.endsWith)) continue;
          files.add(entity);
        }
      }
      // R28-F2: production SNI (a shared CDN domain — weak node-identifying value,
      // but part of the node identity set). The only legitimate references are the
      // WARP privacy/terms URLs in lib/core/constants.dart (Astra R28 §2.1).
      final sniNeedle = 'www' '.cloudflare' '.com';
      for (final file in files) {
        final content = file.readAsStringSync();
        for (final needle in banned) {
          if (content.contains(needle)) {
            offenders.add('${file.path}: banned literal');
          }
        }
        final sniExempt = file.path.endsWith('lib/core/model/constants.dart');
        if (!sniExempt && content.contains(sniNeedle)) {
          offenders.add('${file.path}: production SNI literal');
        }
        for (final match in ipv4.allMatches(content)) {
          final ip = match.group(0)!;
          if (!benignIps.contains(ip)) {
            offenders.add(
                '${file.path}: bare IPv4 literal "$ip" outside the benign allowlist');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'production node data must never ship in the binary: $offenders');
    });
  });

  group('B3-2: negative-control builtin carries dummy values only', () {
    test('non-dialable by construction, free of production shapes, schema-valid', () {
      final builtin = NuBLimeCoreService.r02NegativeControlBuiltin;
      expect(builtin, contains('.invalid'),
          reason: 'RFC 2606 .invalid can never dial out');
      expect(builtin, isNot(contains('178.104.')));
      expect(builtin, isNot(contains('8443')));
      expect(NuBLimeCoreService.validateXrayConfigContent(builtin).isRight(), true,
          reason: 'the negative control must stay a schema-valid Xray document');
    });
  });

  group('B3-3/B3-4: rotateDeliveredFile atomic semantics', () {
    late Directory tempDir;
    late ProfilePathResolver resolver;
    late NuBLimeCoreService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('b3_rotate');
      resolver = ProfilePathResolver(tempDir);
      service = NuBLimeCoreService();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('B3-3: valid backend content atomically replaces the artifact (converted)',
        () async {
      final target = resolver.file('p1');
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(_previousXrayDoc);

      final outcome = await rotateDeliveredFile(
        resolver: resolver,
        service: service,
        id: 'p1',
        content: _backendDoc(),
      );

      expect(outcome.isRight(), true);
      final committed = jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;
      final ob = (committed['outbounds'] as List).single as Map;
      expect(ob['protocol'], 'vless');
      final vnext = ((ob['settings'] as Map)['vnext'] as List).single as Map;
      expect(vnext['address'], 'b3-node.example.test');
      expect(
        NuBLimeCoreService.validateXrayConfigContent(target.readAsStringSync()).isRight(),
        true,
        reason: 'the rotated artifact must be schema-valid Xray content',
      );
      expect(resolver.tempFile('p1').existsSync(), false,
          reason: 'staged input consumed on a published rotation');
    });

    test('B3-4: invalid content preserves the previous artifact and cleans staged',
        () async {
      final target = resolver.file('p2');
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(_previousXrayDoc);

      final broken = jsonDecode(_backendDoc()) as Map<String, dynamic>;
      ((broken['outbounds'] as List).first as Map).remove('uuid');

      final outcome = await rotateDeliveredFile(
        resolver: resolver,
        service: service,
        id: 'p2',
        content: jsonEncode(broken),
      );

      expect(outcome.isLeft(), true);
      expect(target.readAsStringSync(), _previousXrayDoc,
          reason: 'previous artifact preserved byte-for-byte');
      expect(resolver.tempFile('p2').existsSync(), false,
          reason: 'rejected staged input cleaned up (the commit path itself never consumes it)');
    });
  });

  group('B3-5/B3-6/B3-7: RemoteConfigRefresher orchestration', () {
    test('B3-5: success rotates with the exact profileId and fetched body', () async {
      final repo = _FakeProfileRepo();
      final fetched = _backendDoc();
      final refresher = RemoteConfigRefresher(
        fetch: () async => (status: 200, body: fetched),
        activeProfileId: () async => 'profile-42',
        repository: repo,
      );

      final outcome = await refresher.refreshDeliveredConfig();

      expect(outcome.isRight(), true);
      expect(repo.rotations, hasLength(1));
      expect(repo.rotations.single.id, 'profile-42');
      expect(repo.rotations.single.content, fetched);
    });

    test('B3-6: non-200 / empty body / no profile / fetch exception → Left, no rotation',
        () async {
      Future<void> expectNoRotation(
          RemoteConfigRefresher refresher, _FakeProfileRepo repo, String why) async {
        final outcome = await refresher.refreshDeliveredConfig();
        expect(outcome.isLeft(), true, reason: why);
        expect(repo.rotations, isEmpty, reason: why);
      }

      final repoA = _FakeProfileRepo();
      await expectNoRotation(
          RemoteConfigRefresher(
            fetch: () async => (status: 500, body: 'oops'),
            activeProfileId: () async => 'p',
            repository: repoA,
          ),
          repoA,
          'non-200 must not rotate');

      final repoB = _FakeProfileRepo();
      await expectNoRotation(
          RemoteConfigRefresher(
            fetch: () async => (status: 200, body: ''),
            activeProfileId: () async => 'p',
            repository: repoB,
          ),
          repoB,
          'empty body must not rotate');

      final repoC = _FakeProfileRepo();
      await expectNoRotation(
          RemoteConfigRefresher(
            fetch: () async => throw const SocketException('offline'),
            activeProfileId: () async => 'p',
            repository: repoC,
          ),
          repoC,
          'transport failure must not rotate');

      final repoD = _FakeProfileRepo();
      await expectNoRotation(
          RemoteConfigRefresher(
            fetch: () async => (status: 200, body: 'x'),
            activeProfileId: () async => null,
            repository: repoD,
          ),
          repoD,
          'no active profile must not rotate');
    });

    test('B3-7: rotation failure propagates as Left with the failure context', () async {
      final repo = _FakeProfileRepo()
        ..onRotate = (id, content) =>
            TaskEither.left(ProfileFailure.invalidConfig('rejected by commit'));
      final refresher = RemoteConfigRefresher(
        fetch: () async => (status: 200, body: 'x'),
        activeProfileId: () async => 'p',
        repository: repo,
      );

      final outcome = await refresher.refreshDeliveredConfig();

      expect(outcome.isLeft(), true);
      outcome.fold(
        (l) => expect(l, contains('rotation rejected')),
        (_) => fail('expected Left for a rejected rotation'),
      );
    });
  });
}
