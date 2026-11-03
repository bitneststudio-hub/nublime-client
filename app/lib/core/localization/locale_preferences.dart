import 'package:nublime/core/preferences/preferences_provider.dart';
import 'package:nublime/gen/translations.g.dart';
import 'package:nublime/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:io';

part 'locale_preferences.g.dart';

@Riverpod(keepAlive: true)
class LocalePreferences extends _$LocalePreferences with AppLogger {
  @override
  AppLocale build() {
    final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
    if (prefs != null) {
      final persisted = prefs.getString("locale");
      if (persisted != null) {
        if (persisted == "zh") return AppLocale.zhCn;
        try {
          return AppLocale.values.byName(persisted);
        } catch (e) {
          loggy.error("error setting locale: [$persisted]", e);
        }
      }
    }
    // 动态检测系统语言（prefs 未就绪时也走这里）
    final sysLocale = Platform.localeName;
    if (sysLocale.startsWith('zh')) return AppLocale.zhCn;
    return AppLocale.en;
  }

  Future<void> changeLocale(AppLocale value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).requireValue.setString("locale", value.name);
  }

  // 便捷方法：接受字符串
  Future<void> setLocale(String code) async {
    final locale = code.startsWith('zh') ? AppLocale.zhCn : AppLocale.en;
    await changeLocale(locale);
  }
}
