import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:nublime/core/analytics/analytics_controller.dart';
import 'package:nublime/core/app_info/app_info_provider.dart';
import 'package:nublime/core/auth/t59_auth_token_storage.dart';
import 'package:nublime/core/auth/preloaded_auth_token_provider.dart';
import 'package:nublime/core/directories/directories_provider.dart';
import 'package:nublime/core/localization/translations.dart';
import 'package:nublime/core/logger/logger.dart';
import 'package:nublime/core/logger/logger_controller.dart';
import 'package:nublime/core/model/environment.dart';
import 'package:nublime/core/preferences/general_preferences.dart';
import 'package:nublime/core/preferences/preferences_provider.dart';
import 'package:nublime/features/app/widget/app.dart';
import 'package:nublime/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:nublime/features/splash/animated_splash.dart';

import 'package:nublime/features/log/data/log_data_providers.dart';
import 'package:nublime/features/profile/data/profile_data_providers.dart';
import 'package:nublime/features/profile/notifier/active_profile_notifier.dart';
import 'package:nublime/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:nublime/features/window/notifier/window_notifier.dart';
import 'package:nublime/nublimecore/nublime_core_service_provider.dart';
import 'package:nublime/riverpod_observer.dart';
import 'package:nublime/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> lazyBootstrap(WidgetsBinding widgetsBinding, Environment env) async {
  LoggerController.preInit();
  FlutterError.onError = Logger.logFlutterError;
  WidgetsBinding.instance.platformDispatcher.onError = Logger.logPlatformDispatcherError;

  final stopWatch = Stopwatch()..start();

  final container = ProviderContainer(
    overrides: [environmentProvider.overrideWithValue(env)],
  );

  // ── 立即渲染 AnimatedSplash（Flutter 首帧即动画）──
  final splashReady = Completer<void>();
  runApp(
    ProviderScope(
      parent: container,
      observers: [RiverpodObserver()],
      child: AnimatedSplash(
        ready: splashReady.future,
        child: kEnableTelemetry ? SentryUserInteractionWidget(child: const App()) : const App(),
      ),
    ),
  );

  // ── 关键路径：先等 prefs（决定 intro_completed → 路由），再放行 splash ──
  //     prefs 必须在 splash fade 前就绪，因为 App 内 Preferences.introCompleted
  //     的 StateNotifier 构造依赖 sharedPreferencesProvider。
  unawaited(() async {
    try {
      await _init("preferences",
          () => container.read(sharedPreferencesProvider.future));
    } catch (e, st) {
      Logger.bootstrap.error("preferences init failed", e, st);
    }
    try {
      container.read(preloadedAuthTokenProvider.notifier).set(null);
    } catch (_) {}
    Logger.bootstrap.info("critical bootstrap took [${stopWatch.elapsedMilliseconds}ms]");
    if (!splashReady.isCompleted) splashReady.complete();
  }());

  // ── 后台：directories（+ 依赖它的文件日志 sink）──
  unawaited(() async {
    final dirs = await _safeInit("directories",
        () => container.read(appDirectoriesProvider.future));
    if (dirs != null) {
      try {
        LoggerController.init(container.read(logPathResolverProvider).appFile().path);
        Logger.bootstrap.info("environment [$env]");
      } catch (e, st) {
        Logger.bootstrap.error("logger file sink init failed", e, st);
      }
    }
  }());

  // ── 后台：高刷（纯锦上添花）──
  if (!kIsWeb && PlatformUtils.isAndroid) {
    unawaited(_safeInit("android display mode",
        () => FlutterDisplayMode.setHighRefreshRate()));
  }
}

Future<T> _init<T>(String name, Future<T> Function() initializer, {int? timeout}) async {
  final stopWatch = Stopwatch()..start();
  Logger.bootstrap.info("initializing [$name]");
  Future<T> func() => timeout != null ? initializer().timeout(Duration(milliseconds: timeout)) : initializer();
  try {
    final result = await func();
    Logger.bootstrap.debug("[$name] initialized in ${stopWatch.elapsedMilliseconds}ms");
    return result;
  } catch (e, stackTrace) {
    Logger.bootstrap.error("[$name] error initializing", e, stackTrace);
    rethrow;
  } finally {
    stopWatch.stop();
  }
}

Future<T?> _safeInit<T>(String name, Future<T> Function() initializer, {int? timeout}) async {
  try {
    return await _init(name, initializer, timeout: timeout);
  } catch (e) {
    return null;
  }
}
