// lib/features/account/t65_account_page.dart
// T65: Account Info — activation code / expiry / renewal / referral bonus

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/core/auth/t59_auth_token_storage.dart';
import 'package:nublime/core/localization/locale_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class T65AccountPage extends HookConsumerWidget {
  const T65AccountPage({super.key});
  static const _purchaseUrl = 'https://nublime.com/buy';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showCode = useState(false);
    final code = useState<String>('');
    final expiresAt = useState<String>('');
    final bonusDays = useState<int>(0);
    final origExpiry = useState<String>('');
    final locale = ref.watch(localePreferencesProvider);
    final isZh = locale.languageCode == 'zh';

    useEffect(() {
      Future.microtask(() async {
        final storage = AuthTokenStorage();
        final token = await storage.getToken();
        code.value = token?.activationCode ?? '';
        if (token != null) {
          expiresAt.value = '${token.expiresAt.year}-${_pad(token.expiresAt.month)}-${_pad(token.expiresAt.day)}';
          if (token.bonusDays != null && token.bonusDays! > 0) {
            bonusDays.value = token.bonusDays!;
            // Calculate original expiry = current - bonusDays
            final orig = token.expiresAt.subtract(Duration(days: token.bonusDays!));
            origExpiry.value = '${orig.year}-${_pad(orig.month)}-${_pad(orig.day)}';
          }
        }
      });
      return null;
    }, []);

    final isMasked = !showCode.value;
    final hasCode = code.value.isNotEmpty;
    final display = hasCode ? (isMasked ? '•' * code.value.length : code.value) : '';
    final hasBonus = bonusDays.value > 0;

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: NuBLimeColors.text0), onPressed: () => Navigator.pop(context)),
        title: Text(isZh ? '账户信息' : 'Account', style: const TextStyle(color: NuBLimeColors.text0, fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          _Section(title: isZh ? '激活码' : 'Activation Code'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: NuBLimeColors.bg2, borderRadius: BorderRadius.circular(12), border: Border.all(color: NuBLimeColors.border0)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Expanded(child: Text(
                hasCode ? display : '••••••••••••••••••••',
                style: TextStyle(color: hasCode ? NuBLimeColors.text0 : NuBLimeColors.text2, fontSize: 15, fontFamily: 'monospace', letterSpacing: 2),
              )),
              if (hasCode) ...[
                IconButton(icon: Icon(showCode.value ? Icons.visibility_off : Icons.visibility, color: NuBLimeColors.text2, size: 20), onPressed: () => showCode.value = !showCode.value),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy, color: NuBLimeColors.lemon, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code.value));
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Row(children: [
                        const Icon(Icons.check_circle, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(isZh ? '激活码复制成功' : 'Code copied'),
                      ]),
                      backgroundColor: NuBLimeColors.connected,
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ));
                  },
                ),
              ],
            ]),
          ),
          const SizedBox(height: 24),
          _Section(title: isZh ? '到期日期' : 'Expiry Date'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(color: NuBLimeColors.bg2, borderRadius: BorderRadius.circular(12), border: Border.all(color: NuBLimeColors.border0)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.calendar_today, color: NuBLimeColors.lemon, size: 18),
                const SizedBox(width: 12),
                Text(expiresAt.value.isNotEmpty ? expiresAt.value : '--', style: const TextStyle(color: NuBLimeColors.text0, fontSize: 15)),
              ]),
              if (hasBonus) ...[
                const SizedBox(height: 8),
                Divider(color: NuBLimeColors.border0, height: 1),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.card_giftcard, color: NuBLimeColors.lemon, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(TextSpan(
                      style: TextStyle(color: NuBLimeColors.text2, fontSize: 13),
                      children: [
                        TextSpan(text: isZh ? '含推荐获赠 ' : 'Includes referral bonus '),
                        TextSpan(
                          text: '+${bonusDays.value}${isZh ? "天" : "days"}',
                          style: TextStyle(color: NuBLimeColors.lemon, fontWeight: FontWeight.bold),
                        ),
                      ],
                    )),
                  ),
                ]),
                if (origExpiry.value.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.schedule, color: NuBLimeColors.text3, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      isZh ? '原始到期：${origExpiry.value}' : 'Original: ${origExpiry.value}',
                      style: TextStyle(color: NuBLimeColors.text3, fontSize: 12),
                    ),
                  ]),
                ],
              ],
            ]),
          ),
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: () async { try { await launchUrl(Uri.parse(_purchaseUrl), mode: LaunchMode.externalApplication); } catch (_) {} },
              icon: Icon(Icons.autorenew, color: NuBLimeColors.bg0),
              label: Text(isZh ? '续费订阅' : 'Renew Subscription', style: const TextStyle(color: NuBLimeColors.bg0, fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: NuBLimeColors.lemon, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ),
        ])),
      ),
    );
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});
  @override Widget build(BuildContext context) => Text(title, style: const TextStyle(color: NuBLimeColors.text2, fontSize: 13, fontWeight: FontWeight.w500));
}
