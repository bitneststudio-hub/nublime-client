import 'package:fpdart/fpdart.dart';
import 'package:nublime/core/model/directories.dart';
import 'package:nublime/core/preferences/general_preferences.dart';
import 'package:nublime/features/per_app_proxy/data/selected_data_provider.dart';
import 'package:nublime/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:nublime/features/per_app_proxy/model/pkg_flag.dart';
import 'package:nublime/core/router/dialog/dialog_notifier.dart';
import 'package:nublime/core/utils/exception_handler.dart';
import 'package:nublime/features/connection/model/connection_failure.dart';
import 'package:nublime/features/connection/model/connection_status.dart';
import 'package:nublime/features/profile/data/profile_path_resolver.dart';
import 'package:nublime/features/profile/model/profile_entity.dart';
import 'package:nublime/features/settings/data/config_option_repository.dart';
import 'package:nublime/nublimecore/nublime_core_service.dart';
import 'package:nublime/nublimecore/model/singbox_config_option.dart';
import 'package:nublime/nublimecore/model/core_status.dart';
import 'package:nublime/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';

abstract interface class ConnectionRepository {
  SingboxConfigOption? get configOptionsSnapshot;

  TaskEither<ConnectionFailure, Unit> setup();
  Stream<ConnectionStatus> watchConnectionStatus();
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit);
  TaskEither<ConnectionFailure, Unit> disconnect();
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit);

}

class ConnectionRepositoryImpl with ExceptionHandler, InfraLogger implements ConnectionRepository {
  ConnectionRepositoryImpl({
    required this.ref,
    required this.directories,
    required this.singbox,
    required this.configOptionRepository,
    required this.profilePathResolver,
  });

  final Ref ref;

  final Directories directories;
  final NuBLimeCoreService singbox;

  final ConfigOptionRepository configOptionRepository;
  final ProfilePathResolver profilePathResolver;

  SingboxConfigOption? _configOptionsSnapshot;
  @override
  SingboxConfigOption? get configOptionsSnapshot => _configOptionsSnapshot;

  bool _initialized = false;

  @override
  TaskEither<ConnectionFailure, Unit> setup() {
    if (_initialized) return TaskEither.of(unit);
    return exceptionHandler(() {
      loggy.debug("setting up singbox");

      return singbox
          .setup()
          .map((r) {
            _initialized = true;
            return r;
          })
          .mapLeft(UnexpectedConnectionFailure.new)
          .run();
    }, UnexpectedConnectionFailure.new);
  }

  @override

  @override
  Stream<ConnectionStatus> watchConnectionStatus() {
    print("[watchConnectionStatus] called");
    // §4.3: session anchoring happens in the core service (only the accepted session may publish).
    // Here we only enforce monotonic sequence, and we NEVER re-anchor on an incoming id —
    // a late event from a superseded attempt must not be able to reset the filter.
    var lastSeq = -1;
    return singbox.watchStatus().where((e) {
      if (e.seq > 0 && e.seq <= lastSeq) {
        print('[watchConnectionStatus] dropped out-of-order event seq=${e.seq} <= $lastSeq');
        return false;
      }
      if (e.seq > 0) lastSeq = e.seq;
      return true;
    }).map(
      (e) => switch (e.status) {
        CoreStopped() => Disconnected(e.status.getCoreAlert()),
        CoreStarting() => const Connecting(),
        CoreStarted() => const Connected(),
        CoreStopping() => const Disconnecting(),
      },
    );
  }

  /// R36-A05：分应用代理以前只存在于偏好与 UI 里，连接这条路上没人读它 ——
  /// Kotlin 侧因此永远全量代理。这里在每次 start/restart 前把「模式 + 勾选的包」
  /// 冻结成快照随命令下发。查询失败不阻塞连接（退回全量），但要留痕。
  Future<({String mode, List<String> packages})> _perAppSnapshot() async {
    try {
      final appMode = ref.read(Preferences.perAppProxyMode).toAppProxy();
      if (appMode == null) return (mode: 'off', packages: const <String>[]);
      final entries = await ref.read(appProxyDataSourceProvider).watchAll(mode: appMode).first;
      final selected = entries
          .where(
            (e) =>
                !PkgFlag.forceDeselection.check(e.flags) &&
                (PkgFlag.userSelection.check(e.flags) || PkgFlag.autoSelection.check(e.flags)),
          )
          .map((e) => e.pkgName)
          .toList();
      loggy.info('per-app snapshot mode=$appMode selected=${selected.length}');
      return (mode: appMode == AppProxyMode.include ? 'include' : 'exclude', packages: selected);
    } catch (e) {
      loggy.warning('per-app snapshot failed, falling back to full tunnel: $e');
      return (mode: 'off', packages: const <String>[]);
    }
  }

  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit) => setup().flatMap(
    (_) => applyConfigOption(activeProfile).flatMap(
      (_) => TaskEither<ConnectionFailure, Unit>(() async {
        final pa = await _perAppSnapshot();
        return await singbox
            .start(
              profilePathResolver.file(activeProfile.id).path,
              activeProfile.name,
              disableMemoryLimit,
              perAppMode: pa.mode,
              perAppPackages: pa.packages,
            )
            .run();
      }),
    ),
  );

  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => singbox.stop().mapLeft(UnexpectedConnectionFailure.new);

  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      applyConfigOption(activeProfile).flatMap(
        (_) => TaskEither<ConnectionFailure, Unit>(() async {
          final pa = await _perAppSnapshot();
          return await singbox
              .restart(
                profilePathResolver.file(activeProfile.id).path,
                activeProfile.name,
                disableMemoryLimit,
                perAppMode: pa.mode,
                perAppPackages: pa.packages,
              )
              .mapLeft(UnexpectedConnectionFailure.new)
              .run();
        }),
      );

  @visibleForTesting
  TaskEither<ConnectionFailure, Unit> applyConfigOption(ProfileEntity prof) =>
      TaskEither.fromEither(configOptionRepository.fullOptionsOverrided(prof.profileOverride))
          .mapLeft((l) => ConnectionFailure.invalidConfigOption(null, l))
          .flatMap(
            (overridedOptions) => TaskEither.tryCatch(() async {
              _configOptionsSnapshot = overridedOptions;
              await singbox.changeOptions(overridedOptions).run();
              return unit;
            }, (err, st) => err is ConnectionFailure ? err : ConnectionFailure.unexpected(err, st)),
          );
}
