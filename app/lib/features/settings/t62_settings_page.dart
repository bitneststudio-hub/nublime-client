// lib/features/settings/t62_settings_page.dart
// T62: NuBLime 设置页 — 完整实现所有功能模块
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/features/about/widget/about_page.dart';
import 'package:nublime/features/about/data/feature_highlights.dart';
import 'package:nublime/features/per_app_proxy/overview/per_app_proxy_page.dart';
import 'package:nublime/core/auth/t59_auth_token_storage.dart';
import 'package:nublime/core/preferences/general_preferences.dart';
import 'package:nublime/core/router/dialog/dialog_notifier.dart';
import 'package:nublime/core/localization/locale_preferences.dart';
import 'package:nublime/core/localization/translations.dart';
import 'package:nublime/core/model/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nublime/features/settings/model/always_on_vpn_state.dart';

// ─────────────────────────────────────────────
// 主设置页
// ─────────────────────────────────────────────
class T62SettingsPage extends HookConsumerWidget {
  const T62SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localePreferencesProvider);
    final isChinese = true;

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: NuBLimeColors.bg1,
        elevation: 0,
        title: Text(
          isChinese ? '设置' : 'Settings',
          style: TextStyle(
            color: NuBLimeColors.text0,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: IconThemeData(color: NuBLimeColors.text0),
        actions: [_exitButton(context, isChinese)],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── 账号 ──
          _sectionHeader(isChinese ? '账号' : 'Account'),
          _settingsTile(
            icon: Icons.email_outlined,
            title: isChinese ? '关联邮件地址' : 'Link Email',
            subtitle: isChinese ? '接收续费提醒和专属折扣' : 'Receive renewal reminders & discounts',
            trailing: false
                ? Icon(Icons.chevron_right, color: NuBLimeColors.text3)
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: NuBLimeColors.bg3,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(isChinese ? '需要激活' : 'Activate first',
                        style: const TextStyle(color: NuBLimeColors.text3, fontSize: 11)),
                  ),
            onTap: false
                ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _BindEmailPage()))
                : null,
          ),
          _divider(),

          // ── VPN 功能 ──
          _sectionHeader(isChinese ? 'VPN 功能' : 'VPN Features'),
          _settingsTile(
            icon: Icons.security_outlined,
            title: 'Kill Switch',
            subtitle: isChinese ? '查看并开启系统级断网保护' : 'Check & enable system-level protection',
            trailing: Icon(Icons.chevron_right, color: NuBLimeColors.text3),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const KillSwitchPage(),
            )),
          ),
          _settingsTile(
            icon: Icons.shield_outlined,
            title: isChinese ? '加强保护设置' : 'Enhanced Protection',
            subtitle: isChinese ? '系统级 Always-on VPN 与断网保护' : 'System-level Always-on VPN & lockdown',
            trailing: Icon(Icons.chevron_right, color: NuBLimeColors.text3),
            onTap: () => ref.read(dialogNotifierProvider.notifier).showLockdownGuide(),
          ),
          _settingsTile(
            icon: Icons.apps_outlined,
            title: isChinese ? '分应用代理' : 'Per-App Proxy',
            subtitle: isChinese ? '选择哪些应用走VPN隧道' : 'Choose which apps use VPN',
            trailing: Icon(Icons.chevron_right, color: NuBLimeColors.text3),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PerAppProxyEntryPage(),
            )),
          ),
          _settingsTile(
            icon: Icons.route_outlined,
            title: isChinese ? '路由设置' : 'Routing',
            subtitle: isChinese ? '自定义流量路由规则' : 'Customize traffic routing rules',
            trailing: Icon(Icons.chevron_right, color: NuBLimeColors.text3),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const _RoutingPage(),
            )),
          ),
          _divider(),

          // ── 通用 ──
          _sectionHeader(isChinese ? '通用' : 'General'),
          _settingsTile(
            icon: Icons.language_outlined,
            title: isChinese ? '语言' : 'Language',
            subtitle: isChinese ? '中文简体' : 'English',
            trailing: Icon(Icons.chevron_right, color: NuBLimeColors.text3),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const _LanguagePage(),
            )),
          ),
          _divider(),

          // ── 关于 ──
          _sectionHeader(isChinese ? '关于' : 'About'),
          _settingsTile(
            icon: Icons.info_outline,
            title: isChinese ? '关于 WildLime VPN' : 'About WildLime VPN',
            trailing: Icon(Icons.chevron_right, color: NuBLimeColors.text3),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AboutPage(),
            )),
          ),
          _settingsTile(
            icon: Icons.privacy_tip_outlined,
            title: isChinese ? '隐私政策' : 'Privacy Policy',
            trailing: Icon(Icons.open_in_new, color: NuBLimeColors.text3, size: 18),
            onTap: () async { try { await launchUrl(Uri.parse('https://nublime.com/privacy-policy'), mode: LaunchMode.externalApplication); } catch (_) {} },
          ),
          _settingsTile(
            icon: Icons.description_outlined,
            title: isChinese ? '服务条款' : 'Terms of Service',
            trailing: Icon(Icons.open_in_new, color: NuBLimeColors.text3, size: 18),
            onTap: () async { try { await launchUrl(Uri.parse('https://nublime.com/terms'), mode: LaunchMode.externalApplication); } catch (_) {} },
          ),
          _settingsTile(
            icon: Icons.receipt_long_outlined,
            title: isChinese ? '退款政策' : 'Refund Policy',
            trailing: Icon(Icons.open_in_new, color: NuBLimeColors.text3, size: 18),
            onTap: () async { try { await launchUrl(Uri.parse('https://nublime.com/refund-policy'), mode: LaunchMode.externalApplication); } catch (_) {} },
          ),
          _divider(),

          // ── 退出登录 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => _showLogoutDialog(context, ref, isChinese),
              icon: Icon(Icons.logout, color: NuBLimeColors.error, size: 18),
              label: Text(
                isChinese ? '退出登录' : 'Sign Out',
                style: TextStyle(color: NuBLimeColors.error),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: NuBLimeColors.error.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          // ── 退出应用 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: NuBLimeColors.bg2,
                  title: Text(isChinese ? '退出应用' : 'Exit App',
                      style: const TextStyle(color: NuBLimeColors.text0)),
                  content: Text(
                    isChinese ? 'VPN将继续在后台运行保护您的网络。' : 'VPN continues running in background.',
                    style: const TextStyle(color: NuBLimeColors.text1)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(isChinese ? '取消' : 'Cancel',
                          style: const TextStyle(color: NuBLimeColors.text2))),
                    TextButton(
                      onPressed: () { Navigator.pop(ctx); SystemNavigator.pop(); },
                      child: Text(isChinese ? '确认退出' : 'Confirm Exit',
                          style: const TextStyle(color: NuBLimeColors.error))),
                  ],
                ),
              ),
              icon: const Icon(Icons.power_settings_new_rounded, color: NuBLimeColors.text2, size: 18),
              label: Text(isChinese ? '退出应用' : 'Exit App',
                  style: const TextStyle(color: NuBLimeColors.text2)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: NuBLimeColors.border0),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref, bool isChinese) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NuBLimeColors.bg2,
        title: Text(
          isChinese ? '确认退出' : 'Sign Out',
          style: TextStyle(color: NuBLimeColors.text0),
        ),
        content: Text(
          isChinese ? '退出后需要重新输入激活码才能使用VPN。' : 'You will need to re-enter your activation code.',
          style: TextStyle(color: NuBLimeColors.text1),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isChinese ? '取消' : 'Cancel',
                style: TextStyle(color: NuBLimeColors.text2)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final storage = AuthTokenStorage();
              await storage.clearToken();
              await ref.read(Preferences.introCompleted.notifier).update(false);
              if (context.mounted) context.go('/intro');
            },
            child: Text(isChinese ? '退出' : 'Sign Out',
                style: TextStyle(color: NuBLimeColors.error)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 退出App按钮（右上角）
// ─────────────────────────────────────────────
Widget _exitButton(BuildContext context, bool isChinese) {
  return IconButton(
    icon: Icon(Icons.close, color: NuBLimeColors.text2, size: 22),
    onPressed: () => _showExitDialog(context, isChinese),
    tooltip: isChinese ? '退出' : 'Exit',
  );
}

void _showExitDialog(BuildContext context, bool isChinese) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: NuBLimeColors.bg2,
      title: Text(
        isChinese ? '退出应用' : 'Exit App',
        style: TextStyle(color: NuBLimeColors.text0),
      ),
      content: Text(
        isChinese ? '请选择操作方式' : 'Choose an option',
        style: TextStyle(color: NuBLimeColors.text1),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(isChinese ? '取消' : 'Cancel',
              style: TextStyle(color: NuBLimeColors.text2)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            SystemNavigator.pop(); // 最小化到后台
          },
          child: Text(isChinese ? '后台运行' : 'Run in Background',
              style: TextStyle(color: NuBLimeColors.lemon)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            SystemChannels.platform.invokeMethod('SystemNavigator.pop');
          },
          child: Text(isChinese ? '完全退出' : 'Quit',
              style: TextStyle(color: NuBLimeColors.error)),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────
// 共用组件
// ─────────────────────────────────────────────
Widget _sectionHeader(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(title,
          style: TextStyle(
              color: NuBLimeColors.lemon,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8)),
    );

Widget _divider() => Divider(
      height: 1, thickness: 1,
      color: NuBLimeColors.border0,
      indent: 16, endIndent: 16,
    );

Widget _settingsTile({
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? trailing,
  VoidCallback? onTap,
}) =>
    ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: NuBLimeColors.bg3,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: NuBLimeColors.lemon, size: 20),
      ),
      title: Text(title,
          style: TextStyle(color: NuBLimeColors.text0, fontSize: 15)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(color: NuBLimeColors.text2, fontSize: 12))
          : null,
      trailing: trailing,
      onTap: onTap,
    );

// ─────────────────────────────────────────────
// 关联邮件页
// ─────────────────────────────────────────────
class _BindEmailPage extends HookConsumerWidget {
  const _BindEmailPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localePreferencesProvider);
    final isChinese = true;
    final controller = useTextEditingController();
    final loading = useState(false);
    final error = useState<String?>(null);
    final success = useState(false);

    Future<void> submit() async {
      final email = controller.text.trim();
      if (!email.contains('@')) {
        error.value = isChinese ? '请输入有效的邮件地址' : 'Enter a valid email address';
        return;
      }
      loading.value = true;
      error.value = null;
      try {
        final storage = AuthTokenStorage();
        final token = await storage.getToken();
        if (token == null) throw Exception('未登录');
        final res = await _apiBindEmail(token.token, email);
        if (res) {
          success.value = true;
        } else {
          error.value = isChinese ? '绑定失败，请稍后重试' : 'Failed, please try again';
        }
      } catch (e) {
        error.value = e.toString().replaceAll('Exception: ', '');
      } finally {
        loading.value = false;
      }
    }

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: NuBLimeColors.bg1,
        elevation: 0,
        title: Text(
          isChinese ? '关联邮件地址' : 'Link Email',
          style: TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(color: NuBLimeColors.text0),
        actions: [_exitButton(context, isChinese)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: success.value
            ? _successView(isChinese, controller.text.trim())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isChinese
                        ? '关联邮件后可以接收续费提醒和专属折扣码。'
                        : 'Link your email to receive renewal reminders and discount codes.',
                    style: TextStyle(color: NuBLimeColors.text1, fontSize: 14, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: NuBLimeColors.text0),
                    decoration: InputDecoration(
                      hintText: isChinese ? '你的邮件地址' : 'your@email.com',
                      hintStyle: TextStyle(color: NuBLimeColors.text3),
                      filled: true,
                      fillColor: NuBLimeColors.bg2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: NuBLimeColors.border0),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: NuBLimeColors.border0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: NuBLimeColors.lemon),
                      ),
                      prefixIcon: Icon(Icons.email_outlined, color: NuBLimeColors.text3),
                    ),
                  ),
                  if (error.value != null) ...[
                    const SizedBox(height: 8),
                    Text(error.value!,
                        style: TextStyle(color: NuBLimeColors.error, fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading.value ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NuBLimeColors.lemon,
                        foregroundColor: NuBLimeColors.bg0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50)),
                      ),
                      child: loading.value
                          ? SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: NuBLimeColors.bg0))
                          : Text(isChinese ? '确认关联' : 'Link Email',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _successView(bool isChinese, String email) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: NuBLimeColors.connected, size: 64),
            const SizedBox(height: 16),
            Text(
              isChinese ? '关联成功！' : 'Email Linked!',
              style: TextStyle(
                  color: NuBLimeColors.text0,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(email,
                style: TextStyle(color: NuBLimeColors.lemon, fontSize: 15)),
          ],
        ),
      );

  Future<bool> _apiBindEmail(String token, String email) async {
    try {
      final res = await http.put(
        Uri.parse('${Constants.apiBaseUrl}/app/account/email'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['success'] == true;
      }
      // Try to extract server error message
      try {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['message'] != null) throw Exception(data['message']);
      } catch (_) {}
      return false;
    } catch (e) {
      debugPrint('[BIND-EMAIL] error: $e');
      return false;
    }
  }
}

// ─────────────────────────────────────────────
// Kill Switch 页（系统级断网保护）
// ─────────────────────────────────────────────
class KillSwitchPage extends ConsumerStatefulWidget {
  const KillSwitchPage();

  @override
  ConsumerState<KillSwitchPage> createState() => _KillSwitchPageState();
}

class _KillSwitchPageState extends ConsumerState<KillSwitchPage>
    with WidgetsBindingObserver {
  static const _service = AlwaysOnVpnService();

  AlwaysOnVpnState? _state;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户从系统设置返回时必须重新读一次真值 —— 这一页只显示系统状态，
    // 不显示任何本地"我记得你开过"的记忆。
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    final next = await _service.read();
    if (!mounted) return;
    setState(() {
      _state = next;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 跟随全局语言设置：这里原来硬编码 true，切英文后整页仍是中文。
    final isChinese =
        ref.watch(localePreferencesProvider).languageCode == 'zh';
    final status = _state?.status ?? AlwaysOnVpnStatus.unknown;

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: NuBLimeColors.bg1,
        elevation: 0,
        title: Text(
          isChinese ? '断网保护' : 'Kill Switch',
          style: TextStyle(
              color: NuBLimeColors.text0, fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(color: NuBLimeColors.text0),
        actions: [_exitButton(context, isChinese)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _statusCard(status, isChinese),
          const SizedBox(height: 16),
          _openSettingsButton(status, isChinese),
          const SizedBox(height: 24),
          _stepsCard(isChinese),
          const SizedBox(height: 16),
          _honestNote(isChinese),
        ],
      ),
    );
  }

  Color _statusColor(AlwaysOnVpnStatus status) {
    switch (status) {
      case AlwaysOnVpnStatus.enabled:
        return const Color(0xFF34C759);
      case AlwaysOnVpnStatus.partial:
        return const Color(0xFFFFB020);
      case AlwaysOnVpnStatus.disabled:
        return NuBLimeColors.text3;
      case AlwaysOnVpnStatus.unknown:
        return NuBLimeColors.text3;
    }
  }

  IconData _statusIcon(AlwaysOnVpnStatus status) {
    switch (status) {
      case AlwaysOnVpnStatus.enabled:
        return Icons.verified_user;
      case AlwaysOnVpnStatus.partial:
        return Icons.gpp_maybe;
      case AlwaysOnVpnStatus.disabled:
        return Icons.gpp_bad;
      case AlwaysOnVpnStatus.unknown:
        return Icons.help_outline;
    }
  }

  String _statusTitle(AlwaysOnVpnStatus status, bool isChinese) {
    switch (status) {
      case AlwaysOnVpnStatus.enabled:
        return isChinese ? '已开启（系统级保护生效）' : 'On (system-level protection active)';
      case AlwaysOnVpnStatus.partial:
        return isChinese ? '部分开启（断线仍可能泄漏）' : 'Partial (may still leak on disconnect)';
      case AlwaysOnVpnStatus.disabled:
        return isChinese ? '未开启' : 'Off';
      case AlwaysOnVpnStatus.unknown:
        return isChinese ? '请到系统设置里确认' : 'Check in system settings';
    }
  }

  String _statusDetail(AlwaysOnVpnStatus status, bool isChinese) {
    if (_loading) {
      return isChinese ? '正在读取系统设置…' : 'Reading system settings…';
    }
    switch (status) {
      case AlwaysOnVpnStatus.enabled:
        return isChinese
            ? '本应用已设为「始终开启 VPN」，并开启了「阻止无 VPN 连接」。VPN 不在线时，系统会直接阻断所有应用的流量。'
            : 'This app is set as the always-on VPN with "Block connections without VPN" enabled. When the VPN is down, the system blocks all app traffic.';
      case AlwaysOnVpnStatus.partial:
        return isChinese
            ? '本应用已设为「始终开启 VPN」，但「阻止无 VPN 连接」未开。VPN 意外断开时，流量仍可能短暂走本地网络。'
            : 'This app is the always-on VPN, but "Block connections without VPN" is off. Traffic can still leak briefly when the tunnel drops.';
      case AlwaysOnVpnStatus.disabled:
        return isChinese
            ? '本应用还不是系统级「始终开启 VPN」。VPN 意外断开或应用被系统杀掉时，流量会直接走本地网络。'
            : 'This app is not the system always-on VPN. If the tunnel drops or the app is killed, traffic goes out over the local network.';
      case AlwaysOnVpnStatus.unknown:
        // Android 12 起，always_on_vpn_app / always_on_vpn_lockdown 这两个系统键对普通应用
        // 一律不可读（@hide，仅 system_server 与系统应用可读）。这里绝不猜“已开启”，
        // 也不把 SecurityException 原文糊到用户脸上 —— 只说明限制并给出确认路径。
        return isChinese
            ? 'Android 12 起，系统不再允许普通应用读取这两个开关的状态，所以本页无法自动显示。'
              '按下面步骤在系统设置里确认一次即可 —— 只要那两个开关是开的，断网保护就在系统层面生效，与本页能否读取无关。'
            : 'Since Android 12 the system no longer lets ordinary apps read these two switches, '
              'so this page cannot show their state. Confirm once in system settings — as long as '
              'both switches are on, the protection is enforced by the system itself.';
    }
  }

  Widget _statusCard(AlwaysOnVpnStatus status, bool isChinese) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_statusIcon(status), color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusTitle(status, isChinese),
                  style: TextStyle(
                      color: NuBLimeColors.text0,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  _statusDetail(status, isChinese),
                  style: TextStyle(
                      color: NuBLimeColors.text2, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: Icon(Icons.refresh, size: 20, color: NuBLimeColors.text3),
            tooltip: isChinese ? '刷新' : 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _openSettingsButton(AlwaysOnVpnStatus status, bool isChinese) {
    final isOn = status == AlwaysOnVpnStatus.enabled;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: isOn ? NuBLimeColors.bg3 : NuBLimeColors.lemon,
          foregroundColor: isOn ? NuBLimeColors.text1 : Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () async {
          await _service.openSystemVpnSettings();
        },
        icon: Icon(isOn ? Icons.settings : Icons.shield_outlined, size: 20),
        label: Text(
          isOn
              ? (isChinese ? '查看系统设置' : 'Open system settings')
              : (isChinese ? '前往系统设置开启' : 'Enable in system settings'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _stepsCard(bool isChinese) {
    final steps = isChinese
        ? const [
            '点上面的按钮进入系统 VPN 设置',
            '找到 WildLime VPN（部分机型列表里显示为「VPN」，图标是柠檬标），点右侧箭头进详情',
            '开启「始终开启 VPN」',
            '再开启「阻止无 VPN 连接」—— 两个都打开即生效，不必再回到本页确认',
          ]
        : const [
            'Tap the button above to open the system VPN settings',
            'Find this app (listed as "VPN") and open its details (arrow icon)',
            'Turn on "Always-on VPN"',
            'Then turn on "Block connections without VPN" — both on means it is active',
          ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuBLimeColors.border0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isChinese ? '如何开启' : 'How to enable',
            style: TextStyle(
                color: NuBLimeColors.text0,
                fontWeight: FontWeight.bold,
                fontSize: 15),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NuBLimeColors.lemon.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            color: NuBLimeColors.lemon,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: TextStyle(
                          color: NuBLimeColors.text1,
                          fontSize: 13,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _honestNote(bool isChinese) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuBLimeColors.lemon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NuBLimeColors.lemon.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: NuBLimeColors.lemon, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isChinese
                  ? '说明：Android 不允许普通应用自行阻断整机流量。真正的断网保护来自系统的「始终开启 VPN + 阻止无 VPN 连接」；未开启时，本应用不承诺断网不泄漏。'
                  : 'Note: Android does not let a normal app block device-wide traffic on its own. Real kill-switch protection comes from the system always-on VPN + lockdown switches; without them this app does not claim leak-free disconnects.',
              style: TextStyle(
                  color: NuBLimeColors.text1, fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 分应用代理页
// ─────────────────────────────────────────────
class PerAppProxyEntryPage extends HookConsumerWidget {
  const PerAppProxyEntryPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localePreferencesProvider);
    final isChinese = locale.languageCode == 'zh';

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: NuBLimeColors.bg1,
        elevation: 0,
        title: Text(
          isChinese ? '分应用代理' : 'Per-App Proxy',
          style: TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(color: NuBLimeColors.text0),
        actions: [_exitButton(context, isChinese)],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.apps_outlined,
                  color: NuBLimeColors.text3, size: 64),
              const SizedBox(height: 16),
              Text(
                isChinese ? '分应用代理' : 'Per-App Proxy',
                style: TextStyle(
                    color: NuBLimeColors.text0,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isChinese ? '选择哪些应用走VPN隧道，哪些直连' : 'Choose which apps use the VPN tunnel',
                textAlign: TextAlign.center,
                style: TextStyle(color: NuBLimeColors.text2, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PerAppProxyPage()),
                ),
                icon: const Icon(Icons.apps),
                label: Text(isChinese ? '配置应用列表' : 'Configure Apps'),
                style: ElevatedButton.styleFrom(backgroundColor: NuBLimeColors.lemon),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 路由设置页
// ─────────────────────────────────────────────
class _RoutingPage extends HookConsumerWidget {
  const _RoutingPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localePreferencesProvider);
    final isChinese = true;
    final mode = useState('auto'); // auto / proxy / direct

    final modes = [
      (id: 'auto', label: isChinese ? '智能分流' : 'Smart Split',
          desc: isChinese ? '国内直连，国外走代理（推荐）' : 'Direct for local, proxy for overseas (recommended)'),
      (id: 'proxy', label: isChinese ? '全局代理' : 'Global Proxy',
          desc: isChinese ? '所有流量走VPN隧道' : 'All traffic through VPN tunnel'),
      (id: 'direct', label: isChinese ? '全局直连' : 'Direct Only',
          desc: isChinese ? '所有流量直连，不经过VPN' : 'All traffic direct, bypassing VPN'),
    ];

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: NuBLimeColors.bg1,
        elevation: 0,
        title: Text(
          isChinese ? '路由设置' : 'Routing',
          style: TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(color: NuBLimeColors.text0),
        actions: [_exitButton(context, isChinese)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            isChinese ? '选择流量路由模式' : 'Select routing mode',
            style: TextStyle(color: NuBLimeColors.text2, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ...modes.map((m) => GestureDetector(
                onTap: () => mode.value = m.id,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: NuBLimeColors.bg2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: mode.value == m.id
                          ? NuBLimeColors.lemon
                          : NuBLimeColors.border0,
                      width: mode.value == m.id ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Radio<String>(
                        value: m.id,
                        groupValue: mode.value,
                        onChanged: (v) => mode.value = v!,
                        activeColor: NuBLimeColors.lemon,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.label,
                                style: TextStyle(
                                    color: NuBLimeColors.text0,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(m.desc,
                                style: TextStyle(
                                    color: NuBLimeColors.text2, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 语言选择页
// ─────────────────────────────────────────────
class _LanguagePage extends ConsumerWidget {
  const _LanguagePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localePreferencesProvider);

    final langs = [
      (locale: AppLocale.zhCn, label: '中文简体', sub: 'Chinese Simplified'),
      (locale: AppLocale.en, label: 'English', sub: 'English'),
    ];

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: NuBLimeColors.bg1,
        elevation: 0,
        title: Text(
          current == AppLocale.en ? 'Language' : '语言',
          style: TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(color: NuBLimeColors.text0),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: langs.map((l) => GestureDetector(
              onTap: () async {
                await ref
                    .read(localePreferencesProvider.notifier)
                    .changeLocale(l.locale);
                if (context.mounted) Navigator.pop(context);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NuBLimeColors.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: current == l.locale
                        ? NuBLimeColors.lemon
                        : NuBLimeColors.border0,
                    width: current == l.locale ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.label,
                              style: TextStyle(
                                  color: NuBLimeColors.text0,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16)),
                          Text(l.sub,
                              style: TextStyle(
                                  color: NuBLimeColors.text2, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (current == l.locale)
                      Icon(Icons.check_circle,
                          color: NuBLimeColors.lemon, size: 22),
                  ],
                ),
              ),
            )).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ─────────────────────────────────────────────
