// lib/features/about/widget/about_page.dart
// About WildLime VPN — adapted from old About Nublime VPN page

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/features/about/data/feature_highlights.dart';
import 'package:nublime/core/localization/locale_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nublime/features/about/widget/oss_licenses_page.dart';

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

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
          isChinese ? '关于 WildLime VPN' : 'About WildLime VPN',
          style: TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(color: NuBLimeColors.text0),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            // Logo
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: NuBLimeColors.bg2,
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/icon/icon_512x512.png',
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isChinese ? '野柠檬 VPN' : 'WildLime VPN',
              style: TextStyle(
                  color: NuBLimeColors.text0,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            // Version comes from the installed package, not from a literal that drifts every
            // release (it said 4.1.2 while the build was 4.1.10).
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) {
                final info = snap.data;
                return Text(
                  info == null ? 'Version …' : 'Version ${info.version} (Build ${info.buildNumber})',
                  style: TextStyle(color: NuBLimeColors.text3, fontSize: 13),
                );
              },
            ),
            const SizedBox(height: 32),
            _infoCard(isChinese),
            const SizedBox(height: 16),
            _featureCard(isChinese),
            const SizedBox(height: 24),
            Text(
              '© 2026 WildLime VPN Global',
              style: TextStyle(color: NuBLimeColors.text3, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // GPLv3 §6 + MPL-2.0: the licences must be reachable from inside the app.
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OssLicensesPage()),
              ),
              icon: const Icon(Icons.article_outlined, size: 18),
              label: Text(isChinese ? '开源许可与署名' : 'Open-source licences'),
              style: OutlinedButton.styleFrom(
                foregroundColor: NuBLimeColors.lemon,
                side: BorderSide(color: NuBLimeColors.border0),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async { try { await launchUrl(Uri.parse('mailto:support@nublime.com'), mode: LaunchMode.externalApplication); } catch (_) {} },
              child: Text(
                'support@nublime.com',
                style: TextStyle(
                    color: NuBLimeColors.lemon,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: NuBLimeColors.lemon),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async { try { await launchUrl(Uri.parse('https://nublime.com'), mode: LaunchMode.externalApplication); } catch (_) {} },
              child: Text(
                'nublime.com',
                style: TextStyle(
                    color: NuBLimeColors.lemon,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: NuBLimeColors.lemon),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(bool isChinese) => Container(
        width: double.infinity,
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
              isChinese ? '产品介绍' : 'About',
              style: TextStyle(
                  color: NuBLimeColors.lemon,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              isChinese
                  ? 'WildLime VPN（野柠檬 VPN）是专为华人设计的高速 VPN 服务，基于最新加密协议，提供最强隐蔽性和稳定性。'
                  : 'WildLime VPN is a high-speed VPN service designed for Chinese-speaking users, built on the latest encryption protocol for maximum stealth and stability.',
              style: TextStyle(
                  color: NuBLimeColors.text1, fontSize: 14, height: 1.7),
            ),
          ],
        ),
      );

  Widget _featureCard(bool isChinese) {
    final features = FeatureHighlights.of(isChinese: isChinese);
    return Container(
      width: double.infinity,
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
            isChinese ? '核心特性' : 'Key Features',
            style: TextStyle(
                color: NuBLimeColors.lemon,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: NuBLimeColors.lemon, size: 16),
                    const SizedBox(width: 10),
                    Text(f,
                        style: TextStyle(
                            color: NuBLimeColors.text1, fontSize: 14)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
