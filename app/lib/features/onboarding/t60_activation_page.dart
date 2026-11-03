// lib/features/onboarding/t60_activation_page.dart
// T60: 激活码输入界面 - 完整版
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../core/theme/t57_nublime_colors.dart';
import '../../features/profile/data/node_catalog.dart' show nodeConfigEndpoint;
import '../../core/auth/t59_auth_token_storage.dart';
import 'package:nublime/core/preferences/general_preferences.dart';
import 'package:nublime/core/router/go_router/go_router_notifier.dart';
import 'package:nublime/core/preferences/preferences_provider.dart';
import 'package:nublime/features/profile/data/profile_data_providers.dart';
import 'package:nublime/core/localization/locale_preferences.dart';
import 'package:nublime/features/purchase/crypto_purchase_page.dart';

/// 推荐码合法字符集（排除 0 O 1 I L）
final _referralCodeRegExp = RegExp(r'^[A-HJ-NP-Z2-9]{6}$');

class T60ActivationPage extends HookConsumerWidget {
  const T60ActivationPage({super.key});
  static const String _purchaseUrl = 'https://nublime.com/buy';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codeController = useTextEditingController();
    final referralController = useTextEditingController();
    final isLoading = useState(false);
    final errorMessage = useState<String?>(null);
    final deviceId = useState('');
    final locale = ref.watch(localePreferencesProvider);
    final isZh = locale.languageCode == 'zh';

    useEffect(() {
      Future.microtask(() async {
        final storage = AuthTokenStorage();
        deviceId.value = await storage.getOrCreateDeviceId();

        // 剪贴板自动填充推荐码
        try {
          final clip = await Clipboard.getData('text/plain');
          if (clip?.text != null) {
            final cleaned = clip!.text!.toUpperCase().replaceAll(RegExp(r'[^A-HJ-NP-Z2-9]'), '');
            if (_referralCodeRegExp.hasMatch(cleaned)) {
              referralController.text = cleaned;
            }
          }
        } catch (_) {}
      });
      return null;
    }, const []);

    bool _isValidCode(String code) {
      // 统一格式：XXXXX-XXXXX-XXXXX-XXXXX（5-5-5-5，23字符含连字符）
      // 向后兼容纯字母数字不含连字符的格式
      final cleaned = code.replaceAll('-', '');
      if (code == cleaned) {
        // 无连字符：20位纯字母数字
        return RegExp(r'^[A-Z0-9]{20}$').hasMatch(cleaned);
      }
      // 带连字符：5-5-5-5
      return RegExp(r'^[A-Z0-9]{5}\-[A-Z0-9]{5}\-[A-Z0-9]{5}\-[A-Z0-9]{5}$').hasMatch(code);
    }

    // R36-A04：续费叠加必须"话术明示"——以前后端把新码 disabled 并入旧账户，
    // App 一声不响跳首页，用户以为买了新账户（被坑两次）。现在明确告知天数与到期日。
    Future<void> _showRenewalDialog(int days, String? expiry) async {
      final expiryText = expiry == null
          ? (isZh ? '不变' : 'unchanged')
          : expiry.substring(0, 10);
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: NuBLimeColors.bg2,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.autorenew_rounded, color: NuBLimeColors.lemon, size: 48),
            const SizedBox(height: 16),
            Text(
              isZh ? '已叠加续费 $days 天' : '$days days added to your plan',
              style: const TextStyle(color: NuBLimeColors.text0, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isZh
                  ? '这台设备之前已有生效中的订阅，所以本次激活码按"叠加续费"处理：\n'
                    '天数已加到原账户，新到期日 $expiryText。\n'
                    '设备数沿用原账户的名额，不会变成 5 台。'
                  : 'This device already had an active subscription, so this code was applied as a renewal:\n'
                    'the days were added to your existing plan, new expiry $expiryText.\n'
                    'Device slots stay with the original plan, not a new 5-device allowance.',
              style: const TextStyle(color: NuBLimeColors.text2, fontSize: 14, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NuBLimeColors.lemon,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(isZh ? '我知道了' : 'Got it',
                    style: TextStyle(color: NuBLimeColors.bg0, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      );
    }

    Future<void> _showBonusDialog(int bonusDays) async {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: NuBLimeColors.bg2,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.celebration, color: NuBLimeColors.lemon, size: 48),
            const SizedBox(height: 16),
            Text(
              isZh ? '🎉 已获赠 $bonusDays 天' : '🎉 You got $bonusDays free days!',
              style: const TextStyle(color: NuBLimeColors.text0, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isZh ? '推荐奖励已生效，到期日已延长 $bonusDays 天' : 'Referral bonus applied, your expiry has been extended by $bonusDays days.',
              style: const TextStyle(color: NuBLimeColors.text2, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NuBLimeColors.lemon,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(isZh ? '开始使用' : 'Get Started',
                    style: TextStyle(color: NuBLimeColors.bg0, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Image.asset(
                  'assets/icon/icon_512x512.png',
                  width: 80, height: 80,
                ),
              ),
              const SizedBox(height: 24),
              Consumer(builder: (context, ref, _) {
                return Text(isZh ? '野柠檬VPN' : 'WildLime VPN',
                    style: const TextStyle(color: NuBLimeColors.text0, fontSize: 24, fontWeight: FontWeight.bold));
              }),
              const SizedBox(height: 8),
              Text(isZh ? '输入激活码' : 'Enter Activation Code',
                  style: const TextStyle(color: NuBLimeColors.text2, fontSize: 16)),
              const SizedBox(height: 32),
              // ── 激活码输入框 ──
              Container(
                decoration: BoxDecoration(
                  color: NuBLimeColors.bg2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: errorMessage.value != null ? NuBLimeColors.error : NuBLimeColors.border0,
                  ),
                ),
                child: TextField(
                  controller: codeController,
                  maxLength: 23,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: NuBLimeColors.text0, fontSize: 20, letterSpacing: 2, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: isZh ? '激活码：XXXXX-XXXXX-XXXXX-XXXXX' : 'Code: XXXXX-XXXXX-XXXXX-XXXXX',
                    hintStyle: TextStyle(color: NuBLimeColors.text3),
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste, color: NuBLimeColors.text2),
                      tooltip: isZh ? '粘贴' : 'Paste',
                      onPressed: () async {
                        final clipboard = await Clipboard.getData('text/plain');
                        if (clipboard?.text != null) {
                          final cleaned = clipboard!.text!.toUpperCase()
                              .replaceAll(RegExp(r'[^A-Z0-9-]'), '');
                          codeController.text = cleaned.length > 23 ? cleaned.substring(0, 23) : cleaned;
                        }
                      },
                    ),
                  ),
                  onChanged: (_) => errorMessage.value = null,
                ),
              ),
              const SizedBox(height: 16),
              // ── 推荐码输入框（可选） ──
              Container(
                decoration: BoxDecoration(
                  color: NuBLimeColors.bg2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NuBLimeColors.border0),
                ),
                child: TextField(
                  controller: referralController,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: NuBLimeColors.text0, fontSize: 16, letterSpacing: 2, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: isZh ? '推荐码（可选）' : 'Referral code (optional)',
                    hintStyle: TextStyle(color: NuBLimeColors.text3),
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    prefixIcon: Icon(Icons.card_giftcard, color: NuBLimeColors.text3, size: 20),
                  ),
                  onChanged: (_) => errorMessage.value = null,
                ),
              ),
              // ── 错误提示 ──
              if (errorMessage.value != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NuBLimeColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NuBLimeColors.error.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: NuBLimeColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(errorMessage.value!,
                        style: const TextStyle(color: NuBLimeColors.error, fontSize: 13))),
                  ]),
                ),
              ],
              const SizedBox(height: 24),
              // ── 激活按钮 ──
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: isLoading.value ? null : () async {
                    final code = codeController.text.trim().toUpperCase();
                    final refCode = referralController.text.trim().toUpperCase();
                    if (!_isValidCode(code)) {
                      errorMessage.value = isZh ? '激活码无效，请检查格式' : 'Invalid activation code';
                      return;
                    }
                    if (refCode.isNotEmpty && !_referralCodeRegExp.hasMatch(refCode)) {
                      errorMessage.value = isZh ? '推荐码格式不正确（6位字母数字）' : 'Invalid referral code (6 chars)';
                      return;
                    }
                    isLoading.value = true;
                    errorMessage.value = null;
                    try {
                      final body = <String, dynamic>{
                        'activationCode': code,
                        'deviceFingerprint': deviceId.value,
                        'deviceName': 'Android Device',
                        'deviceType': 'android',
                      };
                      if (refCode.isNotEmpty) {
                        body['referralCode'] = refCode;
                      }
                      final response = await http.post(
                        Uri.parse('https://www.nublime.com/api/app/activate'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode(body),
                      );
                      // R09(Astra): 不打印响应内容与 deviceId——响应体含 token，属凭据
                      debugPrint('[ACTIVATE] status=${response.statusCode} body_len=${response.body.length}');
                      if (response.body.isEmpty) throw Exception('Empty response body');
                      final data = jsonDecode(response.body) as Map<String, dynamic>;
                      final success = data['success'] == true || data['success'] == 'true';
                      if (response.statusCode == 200 && success) {
                        // 保存token
                        final storage = AuthTokenStorage();
                        await storage.saveToken(AuthToken(
                          token: data['token'] as String,
                          expiresAt: data['expires_at'] != null
                              ? DateTime.parse(data['expires_at'] as String)
                              : DateTime.now().add(const Duration(days: 365)),
                          deviceId: deviceId.value,
                          createdAt: DateTime.now(),
                          activationCode: code,
                          bonusDays: (data['bonusDays'] as int?) != null && (data['bonusDays'] as int) > 0
                              ? (data['bonusDays'] as int)
                              : (data['referralApplied'] == true ? 7 : null),
                        ));
                        // 获取VPN配置并保存到本地（供连接时使用）
                        try {
                          final jwtToken = data['token'] as String;
                          final configRes = await http.get(
                            Uri.parse(nodeConfigEndpoint()),
                            headers: {'Authorization': 'Bearer $jwtToken'},
                          );
                          if (configRes.statusCode == 200) {
                            final repo = await ref.read(profileRepositoryProvider.future);
                            try { await repo.deleteAll().run(); } catch (_) {}
                            await repo.addLocal(configRes.body).run();
                          }
                        } catch (_) {}
                        // 续费叠加（A-04）：先讲清楚，再跳转
                        if (data['renewalApplied'] == true) {
                          await _showRenewalDialog(
                            (data['renewalDays'] as int?) ?? 0,
                            data['expires_at'] as String?,
                          );
                        }
                        // 显示推荐奖励弹窗（如有），等用户确认后再跳转
                        if (data['referralApplied'] == true) {
                          final bonusDays = data['bonusDays'] as int? ?? 7;
                          await _showBonusDialog(bonusDays);
                        }
                        // 保存奖励信息到 SharedPreferences 供账户页展示（即使 re-activate 也不丢失）
                        final totalBonus = (data['bonusDays'] as int?) ?? 0;
                        if (totalBonus > 0) {
                          final sp = await ref.read(sharedPreferencesProvider.future);
                          await sp.setInt('referral_bonus_days', totalBonus);
                          final origExpiry = data['expires_before_bonus'] as String? ?? data['expires_at'] as String;
                          await sp.setString('referral_original_expiry', origExpiry);
                        }
                        // 标记完成并跳转。跳转必须走 router 实例：这一串 await 之后
                        // context 可能已经不在树上（真机表现为「激活成功但页面不动」）。
                        // 光写 SharedPreferences 不够：redirect 读的是 Preferences.introCompleted
                        // 的当前值，invalidate 后重建时机不定（真机实测仍读到 false 被弹回 /intro）。
                        // 必须同时把 notifier 的内存状态改成 true，再跳。
                        final sp = await ref.read(sharedPreferencesProvider.future);
                        await sp.setBool('intro_completed', true);
                        try {
                          await ref.read(Preferences.introCompleted.notifier).update(true);
                        } catch (e) {
                          debugPrint('[ACTIVATE] introCompleted update failed: $e');
                        }
                        ref.read(goRouterNotiferProvider).go('/home');
                      } else {
                        errorMessage.value = data['message'] as String? ?? (isZh ? '激活码无效' : 'Invalid activation code');
                      }
                    } catch (e) {
                      debugPrint('[ACTIVATE-ERROR] exception=$e');
                      errorMessage.value = isZh ? '网络错误，请检查连接后重试' : 'Network error. Check your connection.';
                    } finally {
                      isLoading.value = false;
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NuBLimeColors.lemon,
                    disabledBackgroundColor: NuBLimeColors.bg3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isLoading.value
                      ? const SizedBox(width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(NuBLimeColors.bg0)))
                      : Text(isZh ? '立即激活' : 'Activate',
                          style: TextStyle(color: NuBLimeColors.bg0, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: Divider(color: NuBLimeColors.border0)),
                Padding(padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(isZh ? '还没有激活码？' : 'No activation code?', style: const TextStyle(color: NuBLimeColors.text3, fontSize: 13))),
                Expanded(child: Divider(color: NuBLimeColors.border0)),
              ]),
              const SizedBox(height: 16),
              // 两种付款方式并列、同一套按钮样式（2026-10-31）：两个都是主入口，
              // 不再用大小区分主次。加密货币走我们自己的后端下单页，支付网关的 key 不进 APK。
              SizedBox(
                width: double.infinity, height: 52,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    try { await launchUrl(Uri.parse(_purchaseUrl), mode: LaunchMode.externalApplication); } catch (_) {}
                  },
                  icon: const Icon(Icons.credit_card, color: NuBLimeColors.lemon, size: 20),
                  label: Text(
                    isZh ? '使用信用卡付款' : 'Pay by credit card',
                    style: const TextStyle(color: NuBLimeColors.lemon, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: NuBLimeColors.lemon),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity, height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CryptoPurchasePage()),
                  ),
                  icon: const Icon(Icons.currency_bitcoin, color: NuBLimeColors.lemon, size: 20),
                  label: Text(
                    isZh ? '使用加密货币付款' : 'Pay with cryptocurrency',
                    style: const TextStyle(color: NuBLimeColors.lemon, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: NuBLimeColors.lemon),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _trustBadge('🔒', isZh ? '严格无日志' : 'No-Log Policy'),
                const SizedBox(width: 24),
                _trustBadge('✅', isZh ? '未激活可退款' : 'Money-back Guarantee'),
                const SizedBox(width: 24),
                _trustBadge('📱', isZh ? '5台设备' : '5 Devices'),
              ]),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trustBadge(String emoji, String text) {
    return Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 4),
      Text(text, style: const TextStyle(color: NuBLimeColors.text2, fontSize: 11)),
    ]);
  }
}
