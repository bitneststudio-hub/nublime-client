// R02 regression test: the config file handed to `start` must be the server-delivered artefact
// (`configs/<profileId>.json`, the file `upsertRemote` writes), never an embedded/bundled default.
//
// This pins the exact defect Astra reported in R02 ("client start still uses the built-in config"):
//   R02-1  connect hands `configs/<profileId>.json` to the core
//   R02-2  the bytes reaching the core are byte-identical to the delivered payload
//   R02-3  rotating the delivered config changes what restart receives (an embedded copy cannot)
//   R02-4  no bundled xray-config asset exists to shadow the delivery chain
//
// Hand-written fakes instead of a mocking package: the repository only needs `changeOptions`,
// `start`, `restart` and `watchConnectionStatus` from the core service, and `connect` never
// touches `ref`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:nublime/features/connection/data/connection_repository.dart';
import 'package:nublime/features/connection/model/connection_failure.dart';
import 'package:nublime/features/profile/data/profile_path_resolver.dart';
import 'package:nublime/features/profile/model/profile_entity.dart';
import 'package:nublime/features/settings/data/config_option_repository.dart';
import 'package:nublime/core/preferences/preferences_provider.dart';
import 'package:nublime/nublimecore/nublime_core_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Records exactly what the core was asked to run.
/// R02 (Astra §3.2): this is a REPOSITORY PARAMETER-PASSING test only — it proves what the
/// repository hands to the core. What the REAL core then does with the path (read + validate
/// + send content) is covered by test/r02_real_core_consumption_test.dart against the real
/// NuBLimeCoreService with a fake platform channel. Kept deliberately: Astra allowed these
/// as repository tests, not as consumption proof.
class _RecordingCore extends NuBLimeCoreService {
  final List<String> startedWith = [];
  final List<String> restartedWith = [];

  /// R36-A05: 分应用代理必须随命令下发，这里把两段参数记下来供断言。
  final List<({String mode, List<String> packages})> perAppSeen = [];

  @override
  TaskEither<ConnectionFailure, Unit> start(
    String profilePath,
    String name,
    bool disableMemoryLimit, {
    String perAppMode = 'off',
    List<String> perAppPackages = const [],
  }) {
    startedWith.add(profilePath);
    perAppSeen.add((mode: perAppMode, packages: perAppPackages));
    return TaskEither.right(unit);
  }

  @override
  TaskEither<String, Unit> restart(
    String profilePath,
    String name,
    bool disableMemoryLimit, {
    String perAppMode = 'off',
    List<String> perAppPackages = const [],
  }) {
    restartedWith.add(profilePath);
    perAppSeen.add((mode: perAppMode, packages: perAppPackages));
    return TaskEither.right(unit);
  }

  @override
  // The base signature is intentionally `Object` (see nublime_core_service.dart:55).
  TaskEither<String, Unit> changeOptions(Object options) => TaskEither.right(unit);
}

/// `connect`/`reconnect` never dereference `ref`, but the constructor requires one, so derive a
/// real `Ref` from a throwaway container.
/// A provider whose create-callback receives the real `Ref`; `connect` never dereferences it.
final _refProvider = Provider<Ref>((ref) => ref);
late Ref _fakeRef;
late ProviderContainer _container;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profileId = 'a1b2c3d4-delivered-config';
  late Directory tempDir;
  late _RecordingCore core;
  late ProfilePathResolver resolver;
  late ProfileEntity deliveredProfile;

  /// Builds a repository wired to a container whose SharedPreferences are resolved.
  Future<ConnectionRepositoryImpl> buildRepo() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((_) async => prefs)],
    );
    await c.read(sharedPreferencesProvider.future);
    return ConnectionRepositoryImpl(
      ref: _fakeRef,
      directories: (baseDir: tempDir, workingDir: tempDir, tempDir: tempDir),
      singbox: core,
      configOptionRepository: ConfigOptionRepository(
        preferences: prefs,
        getConfigOptions: () => c.read(ConfigOptions.singboxConfigOptions),
      ),
      profilePathResolver: resolver,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // The options provider reads `sharedPreferencesProvider.requireValue`, so it must be overridden.
    _container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((_) async => prefs)],
    );
    _fakeRef = _container.read(_refProvider);
    // FutureProvider must be awaited once so dependents see a resolved value, not AsyncLoading.
    await _container.read(sharedPreferencesProvider.future);
    tempDir = Directory.systemTemp.createTempSync('r02_config_chain');
    core = _RecordingCore();
    resolver = ProfilePathResolver(tempDir);
    deliveredProfile = ProfileEntity.remote(
      id: profileId,
      active: true,
      name: 'server-delivered',
      url: 'https://example.invalid/sub',
      lastUpdate: DateTime.utc(2026, 10, 5),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File deliveredFile() {
    final f = resolver.file(profileId);
    f.parent.createSync(recursive: true);
    return f;
  }

  test('R02-1: connect hands configs/<profileId>.json to the core', () async {
    final repo = await buildRepo();

    deliveredFile().writeAsStringSync('{"outbounds":[{"tag":"server-node"}]}');

    // Surface any failure instead of guessing at it.
    final outcome = await repo.connect(deliveredProfile, false).run();
    print('DIAG left=${outcome.isLeft()} leftVal=${outcome.isLeft() ? outcome.getLeft().toString() : '-'}');
    print('DIAG startedWith=${core.startedWith}');

    expect(core.startedWith, hasLength(1), reason: 'connect must start the core exactly once');
    expect(
      core.startedWith.single,
      deliveredFile().path,
      reason: 'start must consume the profile-id-addressed delivered file',
    );
    expect(core.startedWith.single, endsWith('configs/$profileId.json'));
  });

  test('R02-2: the core receives the delivered bytes verbatim', () async {
    final repo = await buildRepo();

    const serverPayload = '{"outbounds":[{"tag":"rotated-by-server"}]}';
    deliveredFile().writeAsStringSync(serverPayload);

    await repo.connect(deliveredProfile, false).run();

    final handedToCore = File(core.startedWith.single);
    expect(handedToCore.existsSync(), isTrue, reason: 'the core must be handed a real file');
    expect(
      handedToCore.readAsStringSync(),
      serverPayload,
      reason: 'the bytes reaching the core must be the delivered bytes, not a built-in default',
    );
  });

  test('R02-3: rotating the delivered config is visible to the next restart', () async {
    final repo = await buildRepo();

    deliveredFile().writeAsStringSync('{"outbounds":[{"tag":"before-rotation"}]}');
    await repo.connect(deliveredProfile, false).run();

    // The server publishes a rotated config for the SAME profile id.
    deliveredFile().writeAsStringSync('{"outbounds":[{"tag":"after-rotation"}]}');
    await repo.reconnect(deliveredProfile, false).run();

    expect(core.startedWith.single, deliveredFile().path);
    expect(File(core.startedWith.single).existsSync(), isTrue);    expect(core.restartedWith, hasLength(1));
    expect(core.restartedWith.single, deliveredFile().path);
    expect(
      File(core.restartedWith.single).readAsStringSync(),
      contains('after-rotation'),
      reason: 'a server-side rotation must be visible to the next start/restart — '
          'precisely what an embedded built-in config cannot do',
    );
  });

  test('R02-4: no bundled config asset can shadow the delivery chain', () {
    for (final path in const [
      'assets/xray_config.json',
      'assets/config.json',
      'assets/singbox_config.json',
    ]) {
      expect(File(path).existsSync(), isFalse,
          reason: '$path must not exist — a bundled config would shadow server delivery');
    }
    // And the delivery path itself is the only source: configs/<id>.json.
    expect(resolver.file(profileId).path, endsWith('configs/$profileId.json'));
  });
}

// Placeholder never used; kept out of the test bodies above.
SharedPreferences await0() => throw UnimplementedError();