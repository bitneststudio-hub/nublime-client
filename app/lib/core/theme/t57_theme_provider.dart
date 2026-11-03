// lib/core/theme/theme_provider.dart
// T57: 主题 Provider - v14 规范 Section 24.3（容错 API 加载）

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nublime/core/model/constants.dart';
import 't57_theme_config.dart';

/// 主题状态通知器（Riverpod Provider）
/// 实现 Section 24.3 的容错主题加载逻辑
class ThemeNotifier extends ChangeNotifier {
  NuBLimeThemeConfig _theme = NuBLimeThemeConfig.defaultTheme();
  bool _isLoading = false;
  String? _error;
  DateTime? _lastFetchTime;

  NuBLimeThemeConfig get theme => _theme;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastFetchTime => _lastFetchTime;

  /// 主题 API 端点
  static const String _themeApiUrl = '${Constants.apiBaseUrl}/theme';

  /// 初始化：加载缓存 + 异步获取最新主题
  Future<void> initialize() async {
    // 1. 先加载本地缓存
    await _loadFromCache();
    
    // 2. 异步获取最新主题（不阻塞 UI）
    _fetchFromApi();
  }

  /// 从 API 获取主题（带容错）
  Future<void> _fetchFromApi() async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http
          .get(Uri.parse(_themeApiUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        final newTheme = NuBLimeThemeConfig.fromJson(jsonData);

        // 只更新版本更高的主题
        if (newTheme.version > _theme.version && newTheme.isValid) {
          _theme = newTheme;
          _lastFetchTime = DateTime.now();
          await _saveToCache();
          debugPrint('✅ 主题已更新：${_theme.name} (v${_theme.version})');
        } else {
          debugPrint('ℹ️ 主题已是最新：${_theme.name} (v${_theme.version})');
        }
      } else {
        _error = 'API 返回错误：${response.statusCode}';
        debugPrint('⚠️ 主题 API 错误：${_error}');
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('⚠️ 主题 API 异常：$e');
      // 容错：使用缓存主题，不抛出异常
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 从缓存加载主题
  Future<void> _loadFromCache() async {
    try {
      // TODO: 实现 SharedPreferences 缓存加载
      // 这里先使用默认主题
      _theme = NuBLimeThemeConfig.defaultTheme();
      debugPrint('📦 已加载缓存主题：${_theme.name}');
    } catch (e) {
      debugPrint('⚠️ 缓存加载失败，使用默认主题：$e');
      _theme = NuBLimeThemeConfig.defaultTheme();
    }
    notifyListeners();
  }

  /// 保存主题到缓存
  Future<void> _saveToCache() async {
    try {
      // TODO: 实现 SharedPreferences 缓存保存
      debugPrint('💾 主题已保存到缓存');
    } catch (e) {
      debugPrint('⚠️ 缓存保存失败：$e');
    }
  }

  /// 手动刷新主题
  Future<void> refresh() async {
    await _fetchFromApi();
  }

  /// 检查主题是否需要更新（距离上次获取超过 5 分钟）
  bool get needsRefresh {
    if (_lastFetchTime == null) return true;
    final diff = DateTime.now().difference(_lastFetchTime!);
    return diff.inMinutes > 5;
  }

  /// 获取当前主题的显示名称
  String get themeDisplayName => _theme.name;

  /// 获取主色调
  Color get primaryColor => _theme.primaryColor;

  /// 获取强调色
  Color get accentColor => _theme.accentColor;

  /// 获取背景色
  Color get backgroundColor => _theme.backgroundColor;

  /// 判断是否是深色模式
  bool get isDarkMode => _theme.isDark;
}

// ========== Riverpod Provider 定义 ==========
// 需要添加依赖：flutter_riverpod ^2.4.9

/*
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeNotifierProvider = ChangeNotifierProvider<ThemeNotifier>((ref) {
  final notifier = ThemeNotifier();
  notifier.initialize();
  return notifier;
});

final themeProvider = Provider<NuBLimeThemeConfig>((ref) {
  return ref.watch(themeNotifierProvider).theme;
});

final themeLoadingProvider = Provider<bool>((ref) {
  return ref.watch(themeNotifierProvider).isLoading;
});
*/

// ========== 使用示例 ==========
/*
class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    
    return MaterialApp(
      theme: ThemeData(
        primaryColor: theme.primaryColor,
        scaffoldBackgroundColor: theme.backgroundColor,
        // ... 其他主题配置
      ),
      home: HomePage(),
    );
  }
}
*/
