// lib/core/theme/theme_config.dart
// T57: 主题配置 - v14 规范 Section 24.3

import 'package:flutter/material.dart';
import 't57_nublime_colors.dart';

/// NuBLime 主题配置模型
/// 支持从 API 动态加载主题（Section 24.3）
class NuBLimeThemeConfig {
  final String id;
  final String name;
  final int version;
  final DateTime validFrom;
  final DateTime validUntil;
  final Color primaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final String? backgroundImageUrl;
  final bool isDark;

  const NuBLimeThemeConfig({
    required this.id,
    required this.name,
    required this.version,
    required this.validFrom,
    required this.validUntil,
    this.primaryColor = NuBLimeColors.lemon,
    this.accentColor = NuBLimeColors.lemonDim,
    this.backgroundColor = NuBLimeColors.bg0,
    this.backgroundImageUrl,
    this.isDark = true,
  });

  /// 默认主题（柠檬绿）
  factory NuBLimeThemeConfig.defaultTheme() {
    return NuBLimeThemeConfig(
      id: 'default',
      name: 'WildLime 默认',
      version: 1,
      validFrom: DateTime(2026, 1, 1),
      validUntil: DateTime(2099, 12, 31),
      primaryColor: NuBLimeColors.lemon,
      accentColor: NuBLimeColors.lemonDim,
      backgroundColor: NuBLimeColors.bg0,
      isDark: true,
    );
  }

  /// 春节主题（红色 + 金）
  factory NuBLimeThemeConfig.springFestival() {
    return NuBLimeThemeConfig(
      id: 'spring_festival',
      name: '🧧 春节',
      version: 1,
      validFrom: DateTime(2026, 1, 28), // 除夕
      validUntil: DateTime(2026, 2, 12), // 元宵 +1
      primaryColor: const Color(0xFFE74C3C), // 红
      accentColor: const Color(0xFFF1C40F), // 金
      backgroundColor: NuBLimeColors.bg0,
      isDark: true,
    );
  }

  /// 圣诞节主题（红 + 绿）
  factory NuBLimeThemeConfig.christmas() {
    return NuBLimeThemeConfig(
      id: 'christmas',
      name: '🎄 圣诞',
      version: 1,
      validFrom: DateTime(2026, 12, 23),
      validUntil: DateTime(2026, 12, 26),
      primaryColor: const Color(0xFFE74C3C), // 圣诞红
      accentColor: const Color(0xFF27AE60), // 圣诞绿
      backgroundColor: NuBLimeColors.bg0,
      isDark: true,
    );
  }

  /// 从 JSON 解析
  factory NuBLimeThemeConfig.fromJson(Map<String, dynamic> json) {
    return NuBLimeThemeConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as int,
      validFrom: DateTime.parse(json['validFrom'] as String),
      validUntil: DateTime.parse(json['validUntil'] as String),
      primaryColor: Color(int.parse(json['primaryColor'] as String, radix: 16)),
      accentColor: Color(int.parse(json['accentColor'] as String, radix: 16)),
      backgroundColor: Color(int.parse(json['backgroundColor'] as String, radix: 16)),
      backgroundImageUrl: json['backgroundImageUrl'] as String?,
      isDark: json['isDark'] as bool? ?? true,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'validFrom': validFrom.toIso8601String(),
      'validUntil': validUntil.toIso8601String(),
      'primaryColor': '0x${primaryColor.value.toRadixString(16)}',
      'accentColor': '0x${accentColor.value.toRadixString(16)}',
      'backgroundColor': '0x${backgroundColor.value.toRadixString(16)}',
      'backgroundImageUrl': backgroundImageUrl,
      'isDark': isDark,
    };
  }

  /// 检查主题是否有效（在有效期内）
  bool get isValid {
    final now = DateTime.now();
    return now.isAfter(validFrom) && now.isBefore(validUntil);
  }

  /// 检查是否是默认主题
  bool get isDefault => id == 'default';

  @override
  String toString() => 'WildLimeThemeConfig($name, v$version, $id)';
}
