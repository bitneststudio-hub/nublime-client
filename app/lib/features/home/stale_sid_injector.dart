// Astra R24 — fault-injection build helpers for the STALE_STOP_SID device scenario.
//
// WHY THIS FILE EXISTS
// --------------------
// R22 §5 could not drive the product's stale-sid branch on device: an external
// `adb am startservice` stop intent is refused by Android's exported-permission
// check, so the stale command never reached the product. R24 therefore reaches
// the same product path from INSIDE the app: the app itself sends a stop command
// naming an already-superseded session id.
//
// The command travels the exact production path (Dart `stop(targetSessionId)` →
// `stopVpn{'sessionId': …}` → XrayVpnService.onStartCommand L315-331), so what
// is verified is the PRODUCT behaviour, not test-only code.
//
// BUILD GATING (identity chain, auditable)
// ---------------------------------------
// The entry is compiled ONLY when the build defines `faultInjection: true`
// (`flutter build apk --dart-define=faultInjection=true`). In every other build
// the flag is a compile-time constant `false`, the triple-tap handler is inert,
// and the title widget's visual output is byte-identical to the pre-R24 build.
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:nublime/nublimecore/nublime_core_service_provider.dart';

/// Compile-time-only switch for the fault-injection entry. Never true in a
/// production/release build; the Dart compiler tree-shakes the dead branch.
const bool kFaultInjectionBuild = bool.fromEnvironment('faultInjection');

/// The fault-injection panel itself. Reachable ONLY from an injection build.
///
/// It sends a stop command naming an explicit (typically stale) session id
/// through the SAME service method the production UI uses (`stop(target)`), so
/// the exercised code path is the product's, not a test double.
class StaleSidInjectorDialog extends ConsumerStatefulWidget {
  final bool isZh;
  const StaleSidInjectorDialog({required this.isZh, super.key}) : super();

  @override
  ConsumerState<StaleSidInjectorDialog> createState() => _StaleSidInjectorDialogState();
}

class _StaleSidInjectorDialogState extends ConsumerState<StaleSidInjectorDialog> {
  final _controller = TextEditingController();
  String? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _inject() async {
    // Route through the real core service, which validates nothing about the
    // target on the Dart side — the PLATFORM (XrayVpnService.onStartCommand)
    // performs the staleness check and refuses if the sid is superseded.
    final target = _controller.text.trim();
    final svc = ref.read(nublimeCoreServiceProvider);
    if (target.isEmpty) {
      setState(() => _result = widget.isZh ? '会话 id 不能为空' : 'session id must not be empty');
      return;
    }
    await svc.stop(target).run();
    setState(() => _result = widget.isZh
        ? '已发送陈旧 sid=$target 的停止命令。'
            '预期：产品校验 sid ≠ 当前会话 → 拒绝执行、在线连接不受影响。'
        : 'Sent a stop command for stale sid=$target. '
            'Expected: the product validates sid != current, refuses, and the live '
            'connection stays up.');
  }

  @override
  Widget build(BuildContext context) {
    final isZh = widget.isZh;
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: Text(
        isZh ? '故障注入 — 陈旧 sid 停止' : 'Fault injection — stale-sid stop',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isZh
                ? 'R22 §5：外部 adb 注入被 Android exported 权限拒绝，故从 app '
                    '内部走同一产品路径驱动陈旧 sid 分支。\n'
                    '输入一个已被接管的会话 id，发送停止命令。产品应在 XrayVpnService '
                    'onStartCommand 校验后拒绝（log: stale stop command ignored），'
                    '在线会话不受影响。'
                : 'R22 §5: external adb injection is refused by Android\'s exported '
                    'permission check, so the stale-sid branch is driven from inside the '
                    'app via the same product path.\n'
                    'Enter an already-superseded session id and send the stop command. '
                    'The product must refuse it in XrayVpnService.onStartCommand '
                    '(log: stale stop command ignored) and leave the live session alone.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: isZh ? '会话 id（12 hex）' : 'session id (12 hex)',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white10,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            Text(
              _result!,
              style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isZh ? '关闭' : 'Close', style: const TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: _inject,
          child: Text(
            isZh ? '发送陈旧停止命令' : 'Send stale stop',
            style: const TextStyle(color: Color(0xFFFFD54F)),
          ),
        ),
      ],
    );
  }
}

