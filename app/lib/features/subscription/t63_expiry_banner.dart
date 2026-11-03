import 'dart:async';
// lib/features/subscription/expiry_banner.dart
// T63: 到期 Banner+ 折扣弹窗 - v14 规范 Section 24.2（withValues）

import 'package:flutter/material.dart';
import '../../core/theme/t57_nublime_colors.dart';

/// 到期提示 Banner 组件
/// 
/// 显示条件：
/// - 订阅剩余时间 < 7 天时显示
/// - 渐变背景 + 续费按钮
/// - 使用 withValues(alpha: X) 而非废弃的 withOpacity
class ExpiryBanner extends StatelessWidget {
  final DateTime expiresAt;
  final VoidCallback? onRenew;

  const ExpiryBanner({
    super.key,
    required this.expiresAt,
    this.onRenew,
  });

  /// 检查是否应该显示 Banner
  bool get shouldShow {
    final now = DateTime.now();
    final diff = expiresAt.difference(now);
    return diff.inDays <= 7;
  }

  /// 获取剩余天数
  int get daysRemaining {
    final now = DateTime.now();
    final diff = expiresAt.difference(now);
    return diff.inDays.clamp(0, 365);
  }

  /// 获取 Banner 颜色（根据剩余天数）
  Color get bannerColor {
    final days = daysRemaining;
    if (days <= 1) {
      return NuBLimeColors.error;
    } else if (days <= 3) {
      return NuBLimeColors.expiring;
    } else {
      return NuBLimeColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldShow) return const SizedBox.shrink();

    final color = bannerColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        // Section 24.2: 使用 withValues 而非 withOpacity
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '订阅即将到期',
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '剩余 $daysRemaining 天，及时续费避免服务中断',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onRenew,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              '续费',
              style: TextStyle(
                color: NuBLimeColors.bg0,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 折扣弹窗组件
/// 
/// 显示场景：
/// - 用户点击续费时
/// - 提供限时折扣（如 8 折、买 10 送 2）
/// - 倒计时营造紧迫感
class DiscountDialog extends StatefulWidget {
  final int discountPercent; // 折扣百分比（如 20 = 8 折）
  final String promoCode;
  final DateTime validUntil;
  final VoidCallback? onApply;

  const DiscountDialog({
    super.key,
    required this.discountPercent,
    required this.promoCode,
    required this.validUntil,
    this.onApply,
  });

  @override
  State<DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<DiscountDialog> {
  late Timer _timer;
  late int _secondsRemaining;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.validUntil.difference(DateTime.now()).inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), _updateTimer);
  }

  void _updateTimer(Timer timer) {
    if (_secondsRemaining > 0) {
      setState(() => _secondsRemaining--);
    } else {
      _timer.cancel();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  /// 格式化倒计时
  String get countdownText {
    final hours = _secondsRemaining ~/ 3600;
    final minutes = (_secondsRemaining % 3600) ~/ 60;
    final seconds = _secondsRemaining % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [NuBLimeColors.bg2, NuBLimeColors.bg3],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuBLimeColors.lemon.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 折扣标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: NuBLimeColors.lemon.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: NuBLimeColors.lemon),
              ),
              child: Text(
                '${100 - widget.discountPercent}% OFF',
                style: TextStyle(
                  color: NuBLimeColors.lemon,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 标题
            Text(
              '限时折扣！',
              style: TextStyle(
                color: NuBLimeColors.text0,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // 描述
            Text(
              '续费立享${widget.discountPercent}%折扣',
              style: TextStyle(
                color: NuBLimeColors.text1,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 20),

            // 促销码
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NuBLimeColors.bg1,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NuBLimeColors.border0),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.promoCode,
                      style: TextStyle(
                        color: NuBLimeColors.lemon,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy, color: NuBLimeColors.text2),
                    onPressed: () {
                      // TODO: 复制到剪贴板
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 倒计时
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, color: NuBLimeColors.text2, size: 16),
                const SizedBox(width: 4),
                Text(
                  '倒计时：$countdownText',
                  style: TextStyle(
                    color: NuBLimeColors.text2,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NuBLimeColors.text2,
                      side: BorderSide(color: NuBLimeColors.border0),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text('稍后再说'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onApply ?? () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NuBLimeColors.lemon,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      '立即使用',
                      style: TextStyle(
                        color: NuBLimeColors.bg0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 显示折扣弹窗的快捷方法
Future<void> showDiscountDialog({
  required BuildContext context,
  int discountPercent = 20,
  String promoCode = 'SAVE20',
  Duration duration = const Duration(minutes: 10),
  VoidCallback? onApply,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => DiscountDialog(
      discountPercent: discountPercent,
      promoCode: promoCode,
      validUntil: DateTime.now().add(duration),
      onApply: onApply,
    ),
  );
}
