import 'package:flutter/material.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/features/connection/notifier/connection_notifier.dart';
import 'package:nublime/features/stats/notifier/stats_notifier.dart';
import 'package:fixnum/fixnum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class StatsPage extends HookConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsNotifierProvider).asData?.value;
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final isConnected = connectionStatus.valueOrNull?.isConnected ?? false;

    final upSpeed = stats?.uplink ?? 0;
    final downSpeed = stats?.downlink ?? 0;
    final upTotal = stats?.uplinkTotal ?? 0;
    final downTotal = stats?.downlinkTotal ?? 0;

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('流量统计',
            style: TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 连接状态
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isConnected
                    ? NuBLimeColors.connected.withValues(alpha: 0.1)
                    : NuBLimeColors.bg2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isConnected ? NuBLimeColors.connected : NuBLimeColors.border0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected ? NuBLimeColors.connected : NuBLimeColors.text3,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isConnected ? 'VPN 已连接' : 'VPN 未连接',
                    style: TextStyle(
                      color: isConnected ? NuBLimeColors.connected : NuBLimeColors.text3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 实时速度
            Row(
              children: [
                Expanded(child: _StatCard(
                  icon: Icons.arrow_upward,
                  color: NuBLimeColors.lemon,
                  label: '上传速度',
                  value: _formatSpeed(upSpeed),
                )),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(
                  icon: Icons.arrow_downward,
                  color: NuBLimeColors.connected,
                  label: '下载速度',
                  value: _formatSpeed(downSpeed),
                )),
              ],
            ),
            const SizedBox(height: 12),

            // 累计流量
            Row(
              children: [
                Expanded(child: _StatCard(
                  icon: Icons.upload,
                  color: NuBLimeColors.lemon.withValues(alpha: 0.7),
                  label: '已上传',
                  value: _formatTotal(upTotal),
                )),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(
                  icon: Icons.download,
                  color: NuBLimeColors.connected.withValues(alpha: 0.7),
                  label: '已下载',
                  value: _formatTotal(downTotal),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatSpeed(int b) {
    if (b <= 0) return '0 B/s';
    if (b < 1024) return '$b B/s';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB/s';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  String _formatTotal(int b) {
    if (b <= 0) return '0 KB';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuBLimeColors.border0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: NuBLimeColors.text2, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(
            color: color, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace',
          )),
        ],
      ),
    );
  }
}
