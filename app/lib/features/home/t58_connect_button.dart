// lib/features/home/t58_connect_button.dart
import 'package:flutter/material.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/features/connection/notifier/connection_notifier.dart';
import 'package:nublime/features/profile/data/profile_data_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../core/auth/t59_auth_token_storage.dart';

class T58ConnectButton extends HookConsumerWidget {
  const T58ConnectButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final status = connectionStatus.valueOrNull;
    final isConnected  = status?.isConnected  ?? false;
    final isConnecting = status?.isSwitching   ?? false;

    final size = MediaQuery.of(context).size.width * 0.6;

    return GestureDetector(
      onTap: () async {
        if (isConnecting) return;
        if (isConnected) {
          ref.read(connectionNotifierProvider.notifier).toggleConnection();
          return;
        }
        // 连接前：确保有 active profile
        try {
          final repo = await ref.read(profileRepositoryProvider.future);
          final result = await repo.getAllProfiles().run();
          result.fold(
            (l) {},
            (profiles) async {
              if (profiles.isNotEmpty && !profiles.any((p) => p.active)) {
                await repo.setAsActive(profiles.first.id).run();
              }
            },
          );
        } catch (_) {}
        ref.read(connectionNotifierProvider.notifier).toggleConnection();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isConnected
              ? NuBLimeColors.connected.withOpacity(0.2)
              : NuBLimeColors.bg0,
          border: Border.all(
            color: isConnected
                ? NuBLimeColors.connected
                : isConnecting
                    ? NuBLimeColors.connecting
                    : NuBLimeColors.lemon,
            width: 3,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isConnected ? Icons.power_settings_new : Icons.power_off,
                color: isConnected
                    ? NuBLimeColors.connected
                    : isConnecting
                        ? NuBLimeColors.connecting
                        : NuBLimeColors.lemon,
                size: 48,
              ),
              const SizedBox(height: 8),
              Text(
                isConnecting ? '连接中...' : isConnected ? '断开' : '连接',
                style: TextStyle(
                  color: isConnected
                      ? NuBLimeColors.connected
                      : isConnecting
                          ? NuBLimeColors.connecting
                          : NuBLimeColors.lemon,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
