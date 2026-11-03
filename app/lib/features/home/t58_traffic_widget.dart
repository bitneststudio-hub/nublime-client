// lib/features/home/t58_traffic_widget.dart
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/features/stats/notifier/stats_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class T58TrafficWidget extends HookConsumerWidget {
  const T58TrafficWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsNotifierProvider).asData?.value;

    final upSpeed   = stats?.uplink        ?? 0;
    final downSpeed = stats?.downlink      ?? 0;
    final upTotal   = stats?.uplinkTotal   ?? 0;
    final downTotal = stats?.downlinkTotal ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuBLimeColors.border0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildItem(
            icon: Icons.arrow_upward,
            color: NuBLimeColors.lemon,
            speed: _formatSpeed(upSpeed),
            total: _formatTotal(upTotal),
            label: '上传',
          ),
          Container(width: 1, height: 40, color: NuBLimeColors.border0),
          _buildItem(
            icon: Icons.arrow_downward,
            color: NuBLimeColors.connected,
            speed: _formatSpeed(downSpeed),
            total: _formatTotal(downTotal),
            label: '下载',
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required IconData icon,
    required Color color,
    required String speed,
    required String total,
    required String label,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: NuBLimeColors.text2, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          speed,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          total,
          style: const TextStyle(color: NuBLimeColors.text3, fontSize: 11),
        ),
      ],
    );
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  String _formatTotal(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
