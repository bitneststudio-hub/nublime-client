import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nublime/core/localization/translations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 帮助对话框
/// 
/// 显示添加配置的帮助信息
class HelpDialog extends HookConsumerWidget {
  const HelpDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return AlertDialog(
      title: const Text('添加配置帮助'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('支持以下方式添加配置：'),
            SizedBox(height: 12),
            Text('• 粘贴订阅链接（URL）'),
            Text('• 扫描二维码'),
            Text('• 手动输入配置'),
            SizedBox(height: 12),
            Text('配置格式支持：'),
            Text('  - V2Ray / Xray'),
            Text('  - Clash'),
            SizedBox(height: 12),
            Text('如有问题，请联系客服获取帮助。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(t.common.ok),
        ),
      ],
    );
  }
}
