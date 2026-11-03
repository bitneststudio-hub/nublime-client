// lib/features/about/widget/oss_licenses_page.dart
// In-app open-source licensing. GPLv3 (this app) and MPL-2.0 (Xray-core) both require the
// license to reach the user with the binary, and GPLv3 §6 requires a source offer — shipping
// the texts only inside the repository is not enough once the APK leaves the build machine.
//
// Three layers, because they answer three different questions:
//   1. 本应用许可   — GPLv3 text + how to obtain the corresponding source (the §6 offer)
//   2. 第三方组件   — the NOTICE verbatim (Xray-core / libXray / hev-socks5-tunnel / Noto Emoji)
//   3. 依赖包许可   — Flutter's licence registry (every pub package, with its own text)

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nublime/core/theme/t57_nublime_colors.dart';

class OssLicensesPage extends StatelessWidget {
  const OssLicensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: NuBLimeColors.bg0,
        appBar: AppBar(
          backgroundColor: NuBLimeColors.bg1,
          elevation: 0,
          iconTheme: IconThemeData(color: NuBLimeColors.text0),
          title: Text(
            '开源许可与署名',
            style: TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            labelColor: NuBLimeColors.lemon,
            unselectedLabelColor: NuBLimeColors.text3,
            indicatorColor: NuBLimeColors.lemon,
            tabs: const [
              Tab(text: '本应用'),
              Tab(text: '第三方组件'),
              Tab(text: '依赖包'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AssetTextTab(asset: 'assets/licenses/GPL-3.0.txt', header: _appLicenseHeader.new),
            _NoticeTab(),
            _PackageLicensesTab(),
          ],
        ),
      ),
    );
  }
}

/// Header shown above the GPLv3 text: who holds the copyright, which build this is, and how to
/// obtain the corresponding source (GPLv3 §6 — a written offer must accompany distribution).
class _appLicenseHeader extends StatelessWidget {
  const _appLicenseHeader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final info = snap.data;
        final version = info == null ? '…' : '${info.version} (${info.buildNumber})';
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NuBLimeColors.bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NuBLimeColors.border0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WildLime VPN $version',
                  style: TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Copyright (C) 2026 BitNest Studio (WildLime).\n'
                '本程序按 GNU 通用公共许可证第 3 版（GPLv3）发布，不提供任何担保。',
                style: TextStyle(color: NuBLimeColors.text1, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 10),
              Text(
                '对应源代码（GPLv3 §6）：本版本的完整源代码随每次分发提供；'
                '公开发布后见公开仓库，在此之前可通过下方邮箱书面索取。',
                style: TextStyle(color: NuBLimeColors.text1, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 10),
              _LinkRow(label: '索取源代码 / 许可问题', url: 'mailto:support@nublime.com'),
              const SizedBox(height: 4),
              _LinkRow(label: 'Xray-core 源码（MPL-2.0）', url: 'https://github.com/XTLS/Xray-core'),
            ],
          ),
        );
      },
    );
  }
}

class _AssetTextTab extends StatelessWidget {
  const _AssetTextTab({required this.asset, this.header = _EmptyHeader.new});

  final String asset;
  final Widget Function() header;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: DefaultAssetBundle.of(context).loadString(asset),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            header(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                snap.data!,
                style: TextStyle(
                  color: NuBLimeColors.text1,
                  fontSize: 12,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyHeader extends StatelessWidget {
  const _EmptyHeader();
  @override
  Widget build(BuildContext context) => const SizedBox(height: 8);
}

class _NoticeTab extends StatelessWidget {
  const _NoticeTab();

  @override
  Widget build(BuildContext context) => const _AssetTextTab(
        asset: 'assets/licenses/NOTICE.txt',
        header: _EmptyHeader.new,
      );
}

/// Flutter's own licence registry: every pub dependency's declaration, rendered by the
/// framework so it stays correct as dependencies change.
class _PackageLicensesTab extends StatelessWidget {
  const _PackageLicensesTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '各依赖包的许可声明由 Flutter 许可注册表生成。',
            style: TextStyle(color: NuBLimeColors.text1, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NuBLimeColors.lemon),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'WildLime VPN',
              applicationLegalese: 'Copyright (C) 2026 BitNest Studio (WildLime). GPLv3.',
            ),
            child: const Text('查看依赖包许可', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        try {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
      child: Text(
        label,
        style: TextStyle(
          color: NuBLimeColors.lemon,
          fontSize: 13,
          decoration: TextDecoration.underline,
          decorationColor: NuBLimeColors.lemon,
        ),
      ),
    );
  }
}
