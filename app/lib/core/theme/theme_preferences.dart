import 'package:nublime/core/preferences/preferences_provider.dart';
import 'package:nublime/core/theme/app_theme_mode.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'theme_preferences.g.dart';

@Riverpod(keepAlive: true)
class ThemePreferences extends _$ThemePreferences {
  @override
  AppThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
    if (prefs == null) return AppThemeMode.system;
    final persisted = prefs.getString("theme_mode");
    if (persisted == null) return AppThemeMode.system;
    return AppThemeMode.values.byName(persisted);
  }

  Future<void> changeThemeMode(AppThemeMode value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).requireValue.setString("theme_mode", value.name);
  }
}
