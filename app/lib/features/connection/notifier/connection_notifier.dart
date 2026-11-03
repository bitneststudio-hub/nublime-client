import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'package:nublime/core/haptic/haptic_service.dart';
import 'package:nublime/core/localization/translations.dart';
import 'package:nublime/core/preferences/general_preferences.dart';
import 'package:nublime/core/preferences/preferences_provider.dart';
import 'package:nublime/core/router/dialog/dialog_notifier.dart';
import 'package:nublime/features/connection/data/connection_data_providers.dart';
import 'package:nublime/features/connection/data/connection_repository.dart';
import 'package:nublime/features/connection/model/connection_failure.dart';
import 'package:nublime/features/connection/model/connection_status.dart';
import 'package:nublime/features/connection/model/network_recovery_window.dart';
import 'package:nublime/features/connection/model/stop_suppression_window.dart';
import 'package:nublime/features/profile/model/profile_entity.dart';
import 'package:nublime/features/profile/data/profile_data_providers.dart';
import 'package:nublime/features/profile/data/remote_config_refresher.dart';
import 'package:nublime/core/auth/auth_token_refresher.dart';
import 'package:nublime/features/profile/data/node_catalog.dart';
import 'package:nublime/features/profile/notifier/active_profile_notifier.dart';
import 'package:nublime/nublimecore/init_signal.dart';
import 'package:nublime/core/utils/single_call.dart';
import 'package:nublime/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

part 'connection_notifier.g.dart';

@Riverpod(keepAlive: true)
class ConnectionNotifier extends _$ConnectionNotifier with AppLogger {
  @override
  Stream<ConnectionStatus> build() {
    loggy.debug("[build] called (sync + explicit bridge)");

    // ── 依赖闸门：repo 构造链（generalPreferences → sharedPreferencesProvider.requireValue）
    // 在 bootstrap 完成前会抛 Bad state（AsyncLoading<SharedPreferences>，真机实测见补审 §2）。
    // 这里声明依赖：prefs 就绪(AsyncData)后 Riverpod 自动重建本 provider，届时才安全 resolve repo。
    // Loading 期间返回空流：state 保持 AsyncLoading，connection_button 对非 AsyncData/AsyncError
    // 的 tap 本来就是 no-op（switch default 分支），无行为副作用。
    ref.onDispose(() {
      _networkWatch?.cancel();
      _networkWatch = null;
    });

    final prefsReady = ref.watch(sharedPreferencesProvider).asData != null;
    if (!prefsReady) {
      loggy.debug("[build] prefs not ready, gate closed (will rebuild on prefs ready)");
      return const Stream<ConnectionStatus>.empty();
    }

    // TODO(iOS): setup 从 await 改为 unawaited，后续订阅不再等待 setup 完成。
    // 当前交付目标仅 Android。启用 iOS 前必须重新评估这里的执行时序。
    if (Platform.isIOS) {
      unawaited(_connectionRepo.setup().mapLeft((l) {
        loggy.error("error setting up connection repository", l);
      }).run());
    }

    listenSelf((previous, next) async {
      if (previous == next) return;
      // A fresh session starts the network-recovery budget from zero again; an explicit
      // user-driven connect also cancels any pending automatic retry.
      if (next.valueOrNull is Connected || next.valueOrNull is Connecting) {
        _networkRecovery.onSessionStarted();
        _cancelNetworkWatch();
      }
      // 依赖闸门（prefs gate）使状态流首次到位时 previous 是 AsyncLoading 而非
      // AsyncData(Disconnected)，故用 valueOrNull 判定"之前未连接"。
      final wasConnected = previous?.valueOrNull?.isConnected ?? false;
      if (!wasConnected) {
        if (next case AsyncData(value: final Connected _)) {
          await ref.read(hapticServiceProvider.notifier).heavyImpact();

          // 注意：不在此处自动设回德国 selector——用户已从下拉选择了国家，
          // 下拉时调 selectOutbound + reconnect，这里再加就覆盖了用户选择。

          if (Platform.isAndroid && !ref.read(Preferences.lockdownGuideShown)) {
            // 首次连接成功：弹一次「系统级加强保护」引导（Always-on + Lockdown）。
            print("[build] lockdown-edge triggered"); // 诊断桩
            await ref.read(Preferences.lockdownGuideShown.notifier).update(true);
            await ref.read(dialogNotifierProvider.notifier).showLockdownGuide();
          }

          if (Platform.isAndroid && !ref.read(Preferences.storeReviewedByUser)) {
            if (await InAppReview.instance.isAvailable()) {
              InAppReview.instance.requestReview();
              ref.read(Preferences.storeReviewedByUser.notifier).update(true);
            }
          }
        }
      }
    });

    ref.listen(activeProfileProvider.select((value) => value.asData?.value), (previous, next) async {
      if (previous == null) return;
      final shouldReconnect = next == null || previous.id != next.id;
      if (shouldReconnect) {
        await reconnect(next);
      }
    });

    ref.watch(coreRestartSignalProvider);

    // ── 显式订阅桥：取代 async* + yield*（该路径曾静默不订阅，真机实测见审核文档 §2.2）──
    final ConnectionRepository repo;
    try {
      repo = _connectionRepo;
    } catch (e, st) {
      // 常驻防御：同类问题若从其他早期依赖复发，显式落正式日志而非静默吞掉。
      loggy.error("connection status bridge: repo resolve threw, subscription NOT established: $e\n$st");
      rethrow;
    }
    final controller = StreamController<ConnectionStatus>();
    final repoStream = repo.watchConnectionStatus();
    loggy.debug("[build] repo stream acquired, subscribing");
    final sub = repoStream.listen(
      (event) {
        loggy.debug("[status-bridge] event: ${event.format()}");
        if (event case Disconnected(connectionFailure: final _?) when PlatformUtils.isDesktop) {
          ref.read(Preferences.startedByUser.notifier).update(false);
        }
        // R01 §7 (Astra R08 C-1): surface the RUNTIME failure reason of the CURRENT session. The
        // old dialog lived in a commented-out listener and only ever fired for command-level
        // errors; a PROBE_FAILED / HEALTH_LOST arriving through the status stream reached the log
        // (format()) but never the interface. Reuse the existing dialog mechanism — no new layout.
        // Deduplicated per session+reason, and never shown for a user-initiated stop.
        _maybeReportRuntimeFailure(event);
        if (!controller.isClosed) controller.add(event);
      },
      onError: (Object e, StackTrace st) {
        loggy.error("[status-bridge] stream error: $e");
        if (!controller.isClosed) controller.addError(e, st);
      },
      cancelOnError: false,
    );
    loggy.debug("[build] bridge subscribed");
    ref.onDispose(() {
      loggy.debug("[build] onDispose: cancelling status subscription");
      sub.cancel();
      controller.close();
    });
    return controller.stream;
  }

  ConnectionRepository get _connectionRepo => ref.read(connectionRepositoryProvider);

  Future<void> mayConnect() async {
    if (state case AsyncData(:final value)) {
      if (value case Disconnected()) return _connect();
    }
  }

  Future<void> toggleConnection() async {
    final haptic = ref.read(hapticServiceProvider.notifier);
    if (state case AsyncError()) {
      await haptic.lightImpact();
      await _connect();
    } else if (state case AsyncData(:final value)) {
      switch (value) {
        case Disconnected():
          await haptic.lightImpact();
          await ref.read(Preferences.startedByUser.notifier).update(true);
          await _connect();
        case Connected():
          // default:
          await haptic.mediumImpact();
          await ref.read(Preferences.startedByUser.notifier).update(false);
          // The user pressed stop while connected: the following disconnect is intentional and
          // must NOT be reported as a runtime fault (§7).
          _stopWindow.armForUserStop();
          // A user stop also cancels any pending network-loss retry — their intent wins.
          _cancelNetworkWatch();
          await _disconnect();
        default:
          loggy.warning("switching status, debounce");
      }
    }
  }

  Future<void> reconnect(ProfileEntity? profile) async {
    if (state case AsyncData(:final value) when value == const Connected()) {
      // F6 (Astra): generation guard — every await below is a boundary where the user may
      // stop, switch profile, or issue a newer restart. The stale command must not deliver
      // its startVpn afterwards.
      final generationAtIssue = ++_restartGeneration;
      if (profile == null) {
        loggy.info("no active profile, disconnecting");
        return _disconnect();
      }
      loggy.info("active profile changed, reconnecting");
      await ref.read(Preferences.startedByUser.notifier).update(true);
      // F6: a stop/newer command during the preference update invalidates this restart.
      if (generationAtIssue != _restartGeneration) {
        loggy.warning("restart superseded before disconnect (generation $generationAtIssue)");
        return;
      }
      // R28-F1 (Astra): the reconnect entry (profile switch / country dropdown) is a
      // fresh connection attempt — it refreshes the backend-delivered config exactly
      // like _connectThrottled. Serialized through the shared single-flight
      // coordinator, so it can never interleave with a connect-path refresh (R28-F3).
      // Failure is logged inside and never blocks the reconnect.
      await _refreshDeliveredConfig();
      // F6: the refresh is another async boundary — a stop/newer command during it
      // invalidates this restart before the platform-side reconnect.
      if (generationAtIssue != _restartGeneration) {
        loggy.warning("restart superseded during refresh (generation $generationAtIssue)");
        return;
      }
      await _connectionRepo.reconnect(profile, ref.read(Preferences.disableMemoryLimit)).mapLeft((err) async {
        // F6: an error from a superseded restart must not surface its dialog.
        if (generationAtIssue != _restartGeneration) {
          loggy.warning("restart error discarded: superseded (generation $generationAtIssue)");
          return;
        }
        loggy.warning("error reconnecting", err);
        state = AsyncError(err, StackTrace.current);
        final t = ref.read(translationsProvider).valueOrNull;
        if (t != null) {
          await ref
              .read(dialogNotifierProvider.notifier)
              .showCustomAlertFromErr(err.present(t));
        }
      }).run();
    }
  }

  /// F6 (Astra): monotonically increasing restart generation. Every restart takes the next
  /// generation; awaits re-check it before each new side effect (disconnect, dialog, state
  /// write) so an outdated restart can never fire a start after a stop.
  int _restartGeneration = 0;

  /// Last runtime failure already surfaced, as "session|reason", to avoid duplicate dialogs.
  String? _lastReportedRuntimeFailure;

  /// [F1] R30-F1: user-stop suppression WINDOW (replaces the F5 one-shot flag).
  /// Armed on user stop/abort; closed only when the NEXT session starts
  /// (Connecting/Connected). While armed, failure terminals of the stopping
  /// session are teardown noise — suppressed from the dialog path and logged.
  /// Rationale: the one-shot flag could be consumed by the FIRST terminal of a
  /// stopping session, so the late SECOND terminal of the double-terminal race
  /// (health failure + clean stop, device 2026-10-20) hit the dialog unguarded.
  /// The window keeps the F5 guarantee: the next session's genuine failures
  /// always surface (Connecting closes the window before they can occur).
  final StopSuppressionWindow _stopWindow = StopSuppressionWindow();

  /// Network-loss recovery: holds a "data path lost" failure back while the device has no
  /// network and reconnects by itself once the network is back (device evidence 2026-10-30).
  final NetworkRecoveryWindow _networkRecovery = NetworkRecoveryWindow();
  Timer? _networkWatch;

  /// Dependency-free reachability probe: a 2 s TCP connect to a public resolver. Returns
  /// false only when the device has no usable path out — which is exactly the condition
  /// that decides whether a "data path lost" failure is the network's fault or ours.
  Future<bool> _networkReachable() async {
    for (final String host in const <String>['1.1.1.1', '8.8.8.8']) {
      try {
        final Socket s = await Socket.connect(host, 443, timeout: const Duration(seconds: 2));
        s.destroy();
        return true;
      } catch (_) {
        // try the next resolver
      }
    }
    return false;
  }

  /// Watches for the network coming back, then performs exactly one automatic reconnect.
  /// Bounded by [NetworkRecoveryWindow.maxAttempts]; every user action cancels it.
  void _startNetworkWatch() {
    _networkWatch?.cancel();
    _networkWatch = Timer.periodic(const Duration(seconds: 3), (Timer timer) async {
      if (!_networkRecovery.isArmed) {
        timer.cancel();
        return;
      }
      if (!await _networkReachable()) return;
      if (!_networkRecovery.onNetworkReachable()) {
        timer.cancel();
        return;
      }
      timer.cancel();
      loggy.warning('[net-recovery] network is back — reconnecting automatically');
      await Future<void>.delayed(_networkRecovery.retryDelay);
      await mayConnect();
    });
  }

  void _cancelNetworkWatch() {
    _networkWatch?.cancel();
    _networkWatch = null;
    _networkRecovery.cancel();
  }


  /// Astra 10-09 §4.1 (LATE_A_FAILED_B): identity for failure dialogs. A status-ENUM check
  /// ("is the UI Connected/Connected now?") cannot tell which session an error belongs to
  /// once the UI is back at Disconnected (A failed → B connected → B failed looks the same
  /// as A's own failure point). Instead every status event advances this epoch; a failure
  /// dialog snapshots the epoch at event time and re-checks it AFTER the translations await
  /// — if any newer event arrived meanwhile (a newer session's transitions or terminal),
  /// this failure belongs to a superseded session and is dropped. B's own failure snapshots
  /// a LATER epoch and still shows.
  int _statusEpoch = 0;

  void _maybeReportRuntimeFailure(ConnectionStatus event) {
    // Every event advances the epoch — the snapshot taken below is the identity binding.
    final eventEpoch = ++_statusEpoch;
    // [F1] R30-F1: the window closes on the NEXT session start (Connecting/Connected).
    _stopWindow.onStatusEvent(event);
    if (event is! Disconnected) {
      // Any non-failed transition clears the dedupe key so a later, different failure can show.
      if (event is Connected || event is Connecting) _lastReportedRuntimeFailure = null;
      return;
    }
    final failure = event.connectionFailure;
    if (failure == null) {
      // [F1] R30-F1: a clean terminal no longer consumes the user-stop window — a late
      // failure terminal from the SAME session's teardown (double-terminal race: health
      // failure + clean stop, device 2026-10-20) must stay suppressed. The F5 guarantee
      // is preserved because the window only closes on the next Connecting/Connected.
      _lastReportedRuntimeFailure = null;
      return;      // a clean disconnect carries no reason
    }
    if (_stopWindow.suppressesFailureTerminal(event)) {
      // [F1] R30-F1: failure terminal within the user-stop window — stopping-session
      // teardown noise (e.g. the observed "data path lost" on disconnect). Log only.
      loggy.warning('[F1] runtime failure within user-stop window suppressed '
          '(stopping-session teardown): $failure');
      return;
    }
    // Dedupe on the failure identity itself: the status stream emits exactly one terminal event
    // per failure, and an identical failure repeating after a new Connecting/Connected cycle is a
    // genuinely new occurrence (the key is cleared on those transitions above).
    final key = '${failure.runtimeType}:${failure.hashCode}';
    if (_lastReportedRuntimeFailure == key) return;   // deduplicated
    _lastReportedRuntimeFailure = key;
    loggy.warning("[status-bridge] runtime failure surfaced", failure);
    // Present the dialog and surface any presentation failure explicitly.
    //
    // translationsProvider is an async FutureProvider and is usually NOT ready when a status event
    // arrives; reading valueOrNull there silently skipped the dialog (observed on device:
    // "t!=null=false" and no dialog ever shown). So we await its readiness with a bounded timeout and
    // fall back to the untranslated error text, which still carries the diagnosable reason.
    () async {
      // Network-loss recovery (device evidence 2026-10-30): when the tunnel dies because the
      // device itself lost its network (airplane mode / tunnel / no signal), the health monitor's
      // "data path lost" is not a service failure — showing it as one was the single worst UX
      // defect in device verification. Hold the dialog back and reconnect once the network returns.
      final String? detail = failure is UnexpectedConnectionFailure ? '${failure.error}' : null;
      if (NetworkRecoveryWindow.looksLikeNetworkLoss(detail)) {
        final bool reachable = await _networkReachable();
        if (_networkRecovery.onFailureOffline(networkReachable: reachable, detail: detail)) {
          loggy.warning("[net-recovery] tunnel lost while the device is offline ($detail) — "
              "holding the failure back and waiting for the network (attempt ${_networkRecovery.attempts + 1})");
          _startNetworkWatch();
          return;
        }
      }
      Translations? t;
      try {
        t = await ref.read(translationsProvider.future).timeout(const Duration(seconds: 3));
      } catch (_) {
        t = null;
      }
      // Astra 10-09 §4.1: identity re-check AFTER the await — the event epoch captured at
      // entry must still be the newest. A newer event (a newer session's Connecting /
      // Connected / terminal) means this failure is from a superseded session: drop it, no
      // matter what the current status ENUM happens to be.
      if (eventEpoch != _statusEpoch) {
        loggy.warning("[status-bridge] late failure dropped: session superseded after await "
            "(epoch $eventEpoch -> $_statusEpoch)");
        return;
      }
      try {
        final shown = t != null
            ? failure.present(t)
            : (type: 'Connection failed', message: '${failure.runtimeType}: $failure');
        await ref.read(dialogNotifierProvider.notifier).showCustomAlertFromErr(shown);
        loggy.warning("[status-bridge] runtime failure dialog presented (translated=${t != null})");
      } catch (e, st) {
        loggy.error("[status-bridge] runtime failure dialog FAILED", e, st);
      }
    }();
  }

  Future<void> abortConnection() async {
    // Astra 10-09 §4.3 (CANCEL_WHILE_COMMAND_PENDING): a user cancel MUST NOT be routed
    // through the same SingleCall gate as the in-flight connect — when the connect command
    // has not returned yet, the gate's busy branch silently DROPS the stop (measured:
    // CANCEL_WHILE_COMMAND_PENDING stopCalls=0). The cancel is a separate, idempotent entry:
    // it invalidates the command generation FIRST (so a late connect/restart receipt cannot
    // publish), then issues the platform stop directly, bypassing the shared gate.
    _restartGeneration++;
    _stopWindow.armForUserStop();
    _cancelNetworkWatch();
    if (state case AsyncData(:final value)) {
      switch (value) {
        case Connected() || Connecting() || Disconnecting():
          loggy.debug("aborting connection");
          // F5 (Astra): an abort during Connecting/Disconnecting is a USER CANCELLATION —
          // the resulting Stopped/HEALTH_LOST must not be reported as a runtime fault,
          // exactly like an explicit stop from the Connected state.
          try {
            await _connectionRepo.disconnect().run();
          } catch (e) {
            loggy.warning("abort disconnect failed", e);
          }
        default:
      }
    }
  }

  final _singleStart = SingleCall();

  Future<void> _connect() async {
    loggy.info('[CONNECT-PATH] _connect() called');
    _singleStart.run(
      () async {
        await _connectThrottled();
      },
      onIgnored: () {
        loggy.debug("connect called while another connect/disconnect is still running, ignoring");
      },
    );
  }

  Future<void> _connectThrottled() async {
    // 连接前请求VPN权限，检查返回值
    if (defaultTargetPlatform == TargetPlatform.android) {
      bool granted = false;
      try {
        final methodChannel = const MethodChannel('com.nublime.app/method');
        granted = await methodChannel.invokeMethod<bool>('requestVpnPermission') ?? false;
      } catch (e) {
        loggy.warning("vpn permission request failed: $e");
        granted = false;
      }
      if (!granted) {
        loggy.warning("vpn permission denied, aborting connect");
        await ref.read(Preferences.startedByUser.notifier).update(false);
        return; // 不进入 connect，不亮绿
      }
    }
    final activeProfile = await ref.read(activeProfileProvider.future);
    if (activeProfile == null) {
      loggy.info("no active profile, not connecting");
      return;
    }
    // B-3 (deployment spec §5, "动态节点下发"): refresh the backend-delivered node
    // config before every connect — rotation and blocked-node switching are
    // backend-driven; the client picks up the new artifact here. A failed refresh
    // NEVER blocks the connect and NEVER falls back to any built-in node (R02/B-3).
    await _refreshDeliveredConfig();
    await _connectionRepo.connect(activeProfile, ref.read(Preferences.disableMemoryLimit)).mapLeft((
      ConnectionFailure err,
    ) async {
      loggy.warning("error connecting", err);
      //Go err is not normal object to see the go errors are string and need to be dumped
      final t2 = ref.read(translationsProvider).valueOrNull;
      if (t2 != null) {
        await ref
            .read(dialogNotifierProvider.notifier)
            .showCustomAlertFromErr(err.present(t2));
      }
      loggy.warning(err);
      if (err.toString().contains("panic")) {
        await Sentry.captureException(Exception(err.toString()));
      }
      await ref.read(Preferences.startedByUser.notifier).update(false);
      state = AsyncError(err, StackTrace.current);
    }).run();
  }

  /// R28-F1/F3 (Astra): single-flight refresh shared by BOTH connection entry points —
  /// the connect path ([_connectThrottled]) and the reconnect path ([reconnect]:
  /// profile switch / country dropdown). The coordinator owns the gate, so the two
  /// entries can never interleave writes to the same per-id staged file; a call that
  /// lands mid-refresh is skipped (a refresh was just attempted). Failures are logged
  /// and swallowed — the connection always proceeds with whatever valid artifact is
  /// on disk, and never falls back to a built-in node (R02 / B-3).
  B3RefreshCoordinator? _refreshCoordinator;

  Future<void> _refreshDeliveredConfig() async {
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      _refreshCoordinator ??= B3RefreshCoordinator(
        refresher: RemoteConfigRefresher(
          fetch: () async {
            // B-3: ask for the user's picked node, or the backend default when none is
            // picked (or the pick no longer exists — SelectedNodeStore is reconciled by the
            // catalog refresh). AuthorizedClient re-reads the token per call (re-activation
            // can rotate it) and renews it once on 401 before giving up.
            final picked = await SelectedNodeStore().read();
            return AuthorizedClient().get(
              Uri.parse(nodeConfigEndpoint(serverId: picked)),
              timeout: const Duration(seconds: 10),
            );
          },
          activeProfileId: () async {
            final p = await ref.read(activeProfileProvider.future);
            return p?.id;
          },
          repository: repo,
        ),
      );
      await _refreshCoordinator!.refreshOnce(
        onSkipped: (reason) => loggy.warning('[B-3] config refresh skipped: $reason'),
        onFailed: (reason) => loggy.warning(
            '[B-3] config refresh failed, connecting with existing artifact: $reason'),
      );
    } catch (e) {
      loggy.warning(
          '[B-3] config refresh failed, connecting with existing artifact: $e');
    }
  }

  Future<void> _disconnect() async {
    _cancelNetworkWatch();
    // Astra 10-09 §4.2: a stop invalidates every in-flight command — the restart/connect
    // generation re-check gates on this counter, so a restart parked on an await cannot
    // fire its startVpn after a user stop has landed.
    _restartGeneration++;
    await _singleStart.run(
      () async {
        await _connectionRepo.disconnect().mapLeft((err) {
          loggy.warning("error disconnecting", err);
          final t3 = ref.read(translationsProvider).valueOrNull;
          if (t3 != null) {
            ref
                .read(dialogNotifierProvider.notifier)
                .showCustomAlertFromErr(err.present(t3));
          }
          state = AsyncError(err, StackTrace.current);
        }).run();
      },
      onIgnored: () {
        loggy.debug("disconnect called while another connect/disconnect is still running, ignoring");
      },
    );
  }
}

@Riverpod(keepAlive: true)
Future<bool> serviceRunning(Ref ref) async {
  // ref.watch(coreRestartSignalProvider);
  return await ref
      .watch(connectionNotifierProvider.selectAsync((data) => data.isConnected))
      .onError((error, stackTrace) => false);
}
