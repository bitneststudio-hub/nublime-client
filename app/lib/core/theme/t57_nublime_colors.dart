// lib/core/theme/nublime_colors.dart
// T57: 色彩系统 - v14 规范 Section 2.1

import 'package:flutter/material.dart';

/// NuBLime VPN 色彩系统
/// 基于 v14 文档 Section 2.1 UI/UX 规范
class NuBLimeColors {
  NuBLimeColors._();

  // ========== 背景色 ==========
  static const Color bg0 = Color(0xFF060C18);  // 最深背景
  static const Color bg1 = Color(0xFF0A0F1E);  // 主背景
  static const Color bg2 = Color(0xFF111827);  // 次级背景
  static const Color bg3 = Color(0xFF1A2235);  // 卡片背景
  static const Color bg4 = Color(0xFF243048);  // 高亮背景

  // ========== 品牌色 ==========
  static const Color lemon = Color(0xFFB8F02A);     // 主品牌色（柠檬绿）
  static const Color lemonDim = Color(0xFF8AB820);  // 暗柠檬绿
  static const Color lemonGlow = Color(0x40B8F02A); // 发光效果（半透明）

  // ========== 连接状态色 ==========
  static const Color connected = Color(0xFF22C55E);     // 已连接（绿色）
  static const Color connecting = Color(0xFFF59E0B);    // 连接中（橙色）
  static const Color disconnected = Color(0xFF374151);  // 未连接（灰色）

  // ========== 功能色 ==========
  static const Color error = Color(0xFFEF4444);       // 错误（红色）
  static const Color expiring = Color(0xFFFF6B2C);    // 即将到期（橙红）
  static const Color warning = Color(0xFFF59E0B);     // 警告（橙色）
  static const Color success = Color(0xFF22C55E);     // 成功（绿色）

  // ========== 文字色 ==========
  static const Color text0 = Color(0xFFF9FAFB);  // 主文字（最亮）
  static const Color text1 = Color(0xFFD1D5DB);  // 次级文字
  static const Color text2 = Color(0xFF9CA3AF);  // 提示文字
  static const Color text3 = Color(0xFF6B7280);  // 禁用文字

  // ========== 边框色 ==========
  static const Color border0 = Color(0xFF1F2D45);  // 主边框
  static const Color border1 = Color(0xFF2D3F5E);  // 次级边框

  // ========== 辅助方法 ==========
  
  /// 获取连接状态文字
  static String getConnectionStatusText(bool isConnected, bool isConnecting) {
    if (isConnecting) return '连接中...';
    if (isConnected) return '已连接';
    return '未连接';
  }

  /// 获取连接状态颜色
  static Color getConnectionStatusColor(bool isConnected, bool isConnecting) {
    if (isConnecting) return connecting;
    if (isConnected) return connected;
    return disconnected;
  }

  /// 获取状态图标
  static String getConnectionStatusIcon(bool isConnected, bool isConnecting) {
    if (isConnecting) return '🔄';
    if (isConnected) return '🟢';
    return '🔴';
  }
}
