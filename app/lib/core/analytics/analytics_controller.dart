import 'package:flutter/foundation.dart';
import 'package:nublime/core/analytics/analytics_filter.dart';
import 'package:nublime/core/analytics/analytics_logger.dart';

import 'package:nublime/core/logger/logger_controller.dart';
import 'package:nublime/core/model/environment.dart';
import 'package:nublime/core/preferences/preferences_provider.dart';
import 'package:nublime/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'analytics_controller.g.dart';

const String enableAnalyticsPrefKey = "enable_analytics";

/// 遥测总开关（编译期）。默认 **关闭**：
/// 只有显式传入 `--dart-define=enable_telemetry=true` 的构建才可能初始化 Sentry，
/// 且仍需用户在设置里手动打开。Windows/Linux 不支持（R-G0-49）。
const bool kEnableTelemetry = bool.fromEnvironment("enable_telemetry", defaultValue: false);

/// 当前平台是否允许遥测：编译期开关 + 移动端平台双重判断。
bool get telemetryAvailable {
  if (!kEnableTelemetry) return false;
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
}

bool _testCrashReport = false;

@Riverpod(keepAlive: true)
class AnalyticsController extends _$AnalyticsController with AppLogger {
  @override
  Future<bool> build() async {
    // 默认关闭：未显式同意前不上报（W-2.1 / 基线 L4）
    return _preferences.getBool(enableAnalyticsPrefKey) ?? false;
  }

  SharedPreferences get _preferences => ref.read(sharedPreferencesProvider).requireValue;

  Future<void> enableAnalytics() async {
    if (!telemetryAvailable) {
      loggy.info("telemetry not available on this build/platform; Sentry stays off");
      await _preferences.setBool(enableAnalyticsPrefKey, false);
      state = const AsyncData(false);
      return;
    }
    if (state case AsyncData(value: final enabled)) {
      loggy.debug("enabling analytics");
      state = const AsyncLoading();
      if (!enabled) {
        await _preferences.setBool(enableAnalyticsPrefKey, true);
      }

      // final env = ref.read(environmentProvider);
      // final appInfo = await ref.read(appInfoProvider.future);
      final dsn = !kDebugMode || _testCrashReport ? Environment.sentryDSN : "";
      if (dsn.isEmpty) {
        loggy.info("no Sentry DSN for this build; analytics stays disabled");
        await _preferences.setBool(enableAnalyticsPrefKey, false);
        state = const AsyncData(false);
        return;
      }
      final sentryLogger = SentryLoggyIntegration();
      LoggerController.instance.addPrinter("analytics", sentryLogger);

      await SentryFlutter.init((options) {
        options.dsn = dsn;
        // options.environment = env.name;
        // options.dist = appInfo.release.name;
        options.debug = kDebugMode;
        options.enableNativeCrashHandling = true;
        options.enableNdkScopeSync = true;
        // options.autoAppStart = false;
        // options.attachScreenshot = true;
        options.serverName = "";
        options.attachThreads = true;
        options.tracesSampleRate = 0.20;
        options.enableUserInteractionTracing = true;
        options.addIntegration(sentryLogger);
        options.beforeSend = sentryBeforeSend;
      });

      state = const AsyncData(true);
    }
  }

  Future<void> disableAnalytics() async {
    if (state case AsyncData()) {
      loggy.debug("disabling analytics");
      state = const AsyncLoading();
      await _preferences.setBool(enableAnalyticsPrefKey, false);
      await Sentry.close();
      LoggerController.instance.removePrinter("analytics");
      state = const AsyncData(false);
    }
  }
}
