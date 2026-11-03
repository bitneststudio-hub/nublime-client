// lib/features/home/wildlime_home_page.dart
// WildLime VPN — v2.5

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:nublime/core/localization/locale_preferences.dart';
import 'package:nublime/core/preferences/preferences_provider.dart';
import 'package:nublime/core/router/go_router/go_router_notifier.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/features/profile/data/profile_data_providers.dart';
import 'package:nublime/features/profile/notifier/active_profile_notifier.dart';
import 'package:nublime/features/home/notifier/node_catalog_provider.dart';
import 'package:nublime/features/profile/data/node_catalog.dart';
import 'package:nublime/features/connection/notifier/connection_notifier.dart';
import 'package:nublime/features/connection/model/connection_status.dart';
import 'package:nublime/features/stats/widget/stats_page.dart';
import 'package:nublime/features/stats/notifier/stats_notifier.dart';
import 'package:nublime/utils/number_formatters.dart';
import 'package:nublime/features/devices/t61_devices_page.dart';
import 'package:nublime/features/account/t65_account_page.dart';
import 'package:nublime/features/about/widget/about_page.dart';
import 'package:nublime/features/referral/t64_referral_page.dart';
import 'package:nublime/features/settings/wildlime_bind_email_page.dart';
import 'package:nublime/core/model/constants.dart';
import 'package:nublime/nublimecore/nublime_core_service_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nublime/core/auth/t59_auth_token_storage.dart';
import 'package:nublime/core/logger/logger.dart';
import 'package:nublime/core/preferences/general_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:nublime/core/router/dialog/dialog_notifier.dart';
import 'package:nublime/features/settings/t62_settings_page.dart';
import 'greetings.dart';
import 'stale_sid_injector.dart';

class WildLimeHomePage extends HookConsumerWidget {
  const WildLimeHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final status = connectionStatus.valueOrNull;
    final isConnected = status?.isConnected ?? false;
    final isSwitching = status?.isSwitching ?? false;
    final locale = ref.watch(localePreferencesProvider);
    final isZh = locale.languageCode == 'zh';
    final selectedCountry = useState<String>('Germany');
    // B-3: backend-driven node picker. Clamped to what the backend can actually render;
    // null == "auto" == ask the backend for its default node.
    final catalog = ref.watch(nodeCatalogProvider).valueOrNull ?? const <NodeInfo>[];
    final pickedNodeId = useState<String?>(null);
    useEffect(() {
      var cancelled = false;
      SelectedNodeStore().read().then((id) {
        if (!cancelled) pickedNodeId.value = id;
      });
      return () => cancelled = true;
    }, const []);
    final cooldown = useState<bool>(false);
    // Astra R24: triple-tap counter for the fault-injection entry. Compiles to a
    // zero-cost field in every non-injection build (never read, tree-shaken).
    final _injectTaps = useState<int>(0);

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      endDrawer: Drawer(
        backgroundColor: NuBLimeColors.bg0,
        width: MediaQuery.of(context).size.width * 0.65,
        child: _HamburgerMenu(ref: ref),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: isConnected
              ? Image.asset('assets/icon/icon_48x48.png', width: 28, height: 28)
              : Image.asset(
                  'assets/icon/nublime_red_48x48.png',
                  width: 28,
                  height: 28,
                ),
        ),
        // Astra R24 fault-injection entry. The original Text widget is preserved
        // VERBATIM below (same text, same colors, same fontSize 17, same w600) and only
        // wrapped by a GestureDetector that is INACTIVE unless the build enables
        // kFaultInjectionBuild — release builds compile to the untouched original.
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: kFaultInjectionBuild
              ? () {
                  _injectTaps.value = (_injectTaps.value == 3) ? 0 : (_injectTaps.value + 1);
                  if (_injectTaps.value == 3) {
                    _injectTaps.value = 0;
                    _openStaleSidInjector(context, ref);
                  }
                }
              : null,
          child: Text(
            isZh ? '野柠檬VPN' : 'WildLime VPN',
            style: TextStyle(
              color: isConnected ? NuBLimeColors.connected : NuBLimeColors.text0,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.menu, color: NuBLimeColors.text0),
              onPressed: () => _showMenu(ctx, ref),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: defaultTargetPlatform == TargetPlatform.android
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final h = constraints.maxHeight;
                    // 小屏保护：低于 560dp 退化为滚动布局，防溢出
                    if (h < 560) {
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            _DailyBlessing(isZh: isZh),
                            const SizedBox(height: 24),
                            Center(
                              child: _ConnectButton(
                                isZh: isZh,
                                cooldown: cooldown,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _NodeSelector(
                              isZh: isZh,
                              nodes: catalog,
                              selectedId: pickedNodeId.value,
                              onChanged: (id) => _onNodeChanged(ref, id, pickedNodeId),
                            ),
                            const SizedBox(height: 4),
                            _TrafficStats(isZh: isZh),
                            const SizedBox(height: 16),
                          ],
                        ),
                      );
                    }
                    // 常规屏：4:6:5:4 弹性呼吸区，剩余空间按比例吸收，无底部死区
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Spacer(flex: 4),
                        _DailyBlessing(isZh: isZh),
                        const Spacer(flex: 6),
                        Center(
                          child: _ConnectButton(isZh: isZh, cooldown: cooldown),
                        ),
                        const Spacer(flex: 5),
                        _NodeSelector(
                              isZh: isZh,
                              nodes: catalog,
                              selectedId: pickedNodeId.value,
                              onChanged: (id) => _onNodeChanged(ref, id, pickedNodeId),
                            ),
                        const SizedBox(height: 4),
                        _TrafficStats(isZh: isZh),
                        const Spacer(flex: 4),
                      ],
                    );
                  },
                )
              : Column(
                  children: [
                    const SizedBox(height: 4),
                    _DailyBlessing(isZh: isZh),
                    const SizedBox(height: 10),
                    _ConnectButton(isZh: isZh, cooldown: cooldown),
                    const Spacer(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NodeSelector(
                              isZh: isZh,
                              nodes: catalog,
                              selectedId: pickedNodeId.value,
                              onChanged: (id) => _onNodeChanged(ref, id, pickedNodeId),
                            ),
                        const SizedBox(height: 2),
                        _TrafficStats(isZh: isZh),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
        ),
      ),
    );
  }

  // 时间戳去抖：用 static 字段（Widget rebuild 也不影响），永不卡死
  // ignore: non_constant_identifier_names
  static DateTime _lastSwitchAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _switchCountry(WidgetRef ref, String country) async {
    // ① 第一行就打印，先于任何 return —— 任何点击都必留痕
    debugPrint('[SWITCH] tap country=$country');
    Logger.bootstrap.info('[SWITCH] tap country=$country');

    // ② 时间戳去抖 1.5s（防连点），永不卡死
    final now = DateTime.now();
    if (now.difference(_lastSwitchAt) < const Duration(milliseconds: 1500)) {
      debugPrint('[SWITCH] debounced country=$country');
      Logger.bootstrap.info('[SWITCH] debounced country=$country');
      return;
    }
    _lastSwitchAt = now;

    // tag 候选（与 _CountryDropdown._countries 的 key 完全一致）
    const candidates = {
      'Germany': ['DE-vless', 'de-vless', 'germany-vless', 'germany'],
      'Australia': ['AU-vless', 'au-vless', 'australia-vless', 'australia'],
      'New Zealand': ['NZ-vless', 'nz-vless', 'newzealand-vless', 'newzealand'],
    };
    final tagCandidates = candidates[country] ?? ['DE-vless'];
    const groupCandidates = ['select']; // 纯 selector，无 proxy/balancer
    Logger.bootstrap.info(
      '[SWITCH] calling selectOutboundWithFallback '
      'groupCandidates=$groupCandidates tagCandidates=$tagCandidates',
    );
    final result = await ref
        .read(nublimeCoreServiceProvider)
        .selectOutboundWithFallback(groupCandidates, tagCandidates)
        .run();
    result.match(
      (err) {
        debugPrint('[SWITCH] FAILED country=$country err=$err');
        Logger.bootstrap.info('[SWITCH] FAILED country=$country err=$err');
      },
      (_) {
        debugPrint('[SWITCH] OK -> $country');
        Logger.bootstrap.info('[SWITCH] OK -> $country');
        // 热切换：只改 selector 指针，不重启 bg/TUN。
        // 重启 bg 会触发 MIUI VPN 权限重新申请 → permission denied → 全局 EPERM。
      },
    );
  }

  /// B-3: persist the pick, then let the connection notifier do the restart. `reconnect`
  /// refreshes the backend-delivered config before restarting the tunnel, and that refresh
  /// reads the pick we just stored — so "switch node" == "new config for THAT node".
  Future<void> _onNodeChanged(
    WidgetRef ref,
    String? serverId,
    ValueNotifier<String?> picked,
  ) async {
    final store = SelectedNodeStore();
    if (serverId == null || serverId.isEmpty) {
      await store.clear();
    } else {
      await store.write(serverId);
    }
    picked.value = serverId;
    final status = ref.read(connectionNotifierProvider).valueOrNull;
    if (status?.isConnected != true) return; // nothing to restart while disconnected
    final profile = await ref.read(activeProfileProvider.future);
    await ref.read(connectionNotifierProvider.notifier).reconnect(profile);
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    Scaffold.of(context).openEndDrawer();
  }

  /// Astra R24: fault-injection panel — inject a stop command for an
  /// ALREADY-SUPERSEDED session id, exercising the product's stale-sid branch
  /// (XrayVpnService.kt onStartCommand L315-331) from inside the app.
  ///
  /// This exists ONLY because an external `adb am startservice` stop intent is
  /// refused by Android's exported-permission check (R22 §5), so the stale-sid
  /// device scenario was otherwise unreachable on device.
  ///
  /// The panel body explains what will happen: the stale sid is validated against
  /// the live attempt, the command is refused, and the live connection keeps
  /// running — the observable proof that a stale command cannot kill the live
  /// generation.
  void _openStaleSidInjector(BuildContext context, WidgetRef ref) {
    final isZh = ref.read(localePreferencesProvider).languageCode == 'zh';
    showDialog(
      context: context,
      builder: (ctx) => StaleSidInjectorDialog(isZh: isZh),
    );
  }
}

// ═══ 每日祝福 ═══
class _DailyBlessing extends HookWidget {
  final bool isZh;
  const _DailyBlessing({required this.isZh});

  static String _todayKey(String lang) {
    final n = DateTime.now();
    return 'daily_blessing_${lang}_${n.year}_${n.month}_${n.day}';
  }

  static String _usedSetKey(String lang) => 'daily_blessing_used_$lang';

  @override
  Widget build(BuildContext context) {
    final greeting = useState<String>('');
    final lang = isZh ? 'zh' : 'en';

    useEffect(() {
      bool mounted = true;
      _pickGreeting(lang).then((g) {
        if (mounted) greeting.value = g;
      });
      return () => mounted = false;
    }, [lang]);

    final display = greeting.value.isEmpty ? '\u2026' : greeting.value;
    final fs = defaultTargetPlatform == TargetPlatform.android ? 18.0 : 12.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: NuBLimeColors.lemon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        display,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: NuBLimeColors.lemon,
          fontSize: fs,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<String> _pickGreeting(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey(lang);
    final cached = prefs.getString(todayKey);
    if (cached != null) return cached;

    final src = lang == 'zh' ? GreetingsData.zh : GreetingsData.en;
    final usedRaw = prefs.getStringList(_usedSetKey(lang)) ?? [];
    final used = usedRaw.map(int.parse).toSet();
    final avail = List.generate(
      src.length,
      (i) => i,
    ).where((i) => !used.contains(i)).toList();

    if (avail.isEmpty) {
      avail.addAll(List.generate(src.length, (i) => i));
      usedRaw.clear();
    }

    final now = DateTime.now();
    final seed = now.year * 1000 + _dayOfYear(now);
    final rng = Random(seed);
    final pick = avail[rng.nextInt(avail.length)];

    usedRaw.add(pick.toString());
    await prefs.setStringList(_usedSetKey(lang), usedRaw);
    await prefs.setString(todayKey, src[pick]);
    return src[pick];
  }

  static int _dayOfYear(DateTime d) {
    final start = DateTime(d.year, 1, 1);
    return d.difference(start).inDays + 1;
  }
}

// ═══ 连接按钮 ═══
class _ConnectButton extends HookConsumerWidget {
  final bool isZh;
  final ValueNotifier<bool> cooldown;
  final double? sizeOverride;
  const _ConnectButton({
    required this.isZh,
    required this.cooldown,
    this.sizeOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = ref.watch(connectionNotifierProvider);
    final s = cs.valueOrNull;
    final isC = s?.isConnected ?? false;
    final isS = s?.isSwitching ?? false;
    final size =
        sizeOverride ?? MediaQuery.of(context).size.width.clamp(180.0, 220.0);
    final b = cooldown.value;
    final color = b
        ? NuBLimeColors.text3
        : isS
        ? NuBLimeColors.connecting
        : isC
        ? NuBLimeColors.connected
        : NuBLimeColors.lemon;
    final label = b
        ? (isZh ? '冷却中…' : 'Cooldown…')
        : isS
        ? (isZh ? '连接中…' : 'Connecting…')
        : isC
        ? (isZh ? '断开' : 'Disconnect')
        : (isZh ? '连接' : 'Connect');

    // ── Animation Controllers ──
    final radarCtrl = useAnimationController(
      duration: const Duration(milliseconds: 2000),
    );
    final breatheCtrl = useAnimationController(
      duration: const Duration(milliseconds: 1400),
    );

    useEffect(() {
      if (isS) {
        radarCtrl.repeat();
      } else {
        radarCtrl.stop();
        radarCtrl.reset();
      }
      return null;
    }, [isS]);

    useEffect(() {
      if (b) {
        breatheCtrl.repeat(reverse: true);
      } else {
        breatheCtrl.stop();
        breatheCtrl.reset();
      }
      return null;
    }, [b]);

    // ── Breathing curve (ease-in-out for organic feel) ──
    final breatheCurve = useMemoized(
      () => CurvedAnimation(parent: breatheCtrl, curve: Curves.easeInOut),
      [breatheCtrl],
    );
    final breatheScale = useMemoized(
      () => Tween<double>(begin: 0.95, end: 1.05).animate(breatheCurve),
      [breatheCurve],
    );

    final activeCtrl = b ? breatheCtrl : radarCtrl;
    final iconSize = defaultTargetPlatform == TargetPlatform.android
        ? 66.0
        : 48.0;
    final labelSize = defaultTargetPlatform == TargetPlatform.android
        ? 24.0
        : 18.0;

    return GestureDetector(
      onTap: b
          ? null
          : () async {
              final cur = ref.read(connectionNotifierProvider).valueOrNull;
              if (cur?.isConnected == true) {
                ref
                    .read(connectionNotifierProvider.notifier)
                    .toggleConnection();
                cooldown.value = true;
                Future.delayed(
                  const Duration(seconds: 5),
                  () => cooldown.value = false,
                );
                return;
              }
              // Astra 10-09 §4.3 (CANCEL_WHILE_COMMAND_PENDING / reachable cancel):
              // a tap while CONNECTING is the user CANCELLING the start — the old flow
              // returned early on isS (switching) before ever reaching a cancel path, so
              // a start could never be cancelled from this (the actual home) button.
              // abortConnection is the dedicated, idempotent cancel entry: it invalidates
              // the command generation first (a late start/stop receipt cannot publish),
              // then issues the platform stop bypassing the shared gate.
              if (cur is Connecting || cur is Disconnecting) {
                await ref
                    .read(connectionNotifierProvider.notifier)
                    .abortConnection();
                cooldown.value = true;
                Future.delayed(
                  const Duration(seconds: 2),
                  () => cooldown.value = false,
                );
                return;
              }
              if (isS) return;
              try {
                final repo = await ref.read(profileRepositoryProvider.future);
                final r = await repo.getAllProfiles().run();
                r.fold((_) {}, (p) async {
                  if (p.isNotEmpty && !p.any((x) => x.active)) {
                    await repo.setAsActive(p.first.id).run();
                  }
                });
              } catch (_) {}
              ref.read(connectionNotifierProvider.notifier).toggleConnection();
            },
      child: AnimatedBuilder(
        animation: activeCtrl,
        builder: (context, child) {
          final scale = b ? breatheScale.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: ClipOval(
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isC
                      ? NuBLimeColors.connected.withValues(alpha: 0.2)
                      : NuBLimeColors.bg0,
                  border: Border.all(color: color, width: 3),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // ── Radar pulse rings during connecting ──
                    if (isS)
                      CustomPaint(
                        size: Size(size, size),
                        painter: _RadarPainter(
                          color: NuBLimeColors.connecting,
                          animationValue: radarCtrl.value,
                        ),
                      ),
                    // ── Icon + label ──
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isC ? Icons.power_settings_new : Icons.power_off,
                            color: color,
                            size: iconSize,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: labelSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Radar / Pulse CustomPainter ──
class _RadarPainter extends CustomPainter {
  final Color color;
  final double animationValue;

  _RadarPainter({required this.color, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final phaseOffset = i / 3.0;
      final ringProgress = (animationValue + phaseOffset) % 1.0;
      final radius = ringProgress * maxRadius;
      final opacity = (1.0 - ringProgress) * 0.25;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + (1.0 - ringProgress) * 1.5;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

// ═══ 节点选择（B-3：后端目录驱动；无选择余地时退回静态标签）═══
class _NodeSelector extends StatelessWidget {
  final bool isZh;
  final List<NodeInfo> nodes;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  const _NodeSelector({
    required this.isZh,
    required this.nodes,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing to choose (single node, catalog fetch failed, or not activated yet):
    // keep the exact single-node look the app shipped with.
    if (!nodes.hasChoice) return _CountryLabel(isZh: isZh);
    return _NodeDropdown(
      isZh: isZh,
      nodes: nodes,
      selectedId: selectedId,
      onChanged: onChanged,
    );
  }
}

class _NodeDropdown extends StatelessWidget {
  final bool isZh;
  final List<NodeInfo> nodes;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  const _NodeDropdown({
    required this.isZh,
    required this.nodes,
    required this.selectedId,
    required this.onChanged,
  });

  /// Sentinel for "let the backend decide" — never a real node id.
  static const String autoValue = '__auto__';

  @override
  Widget build(BuildContext context) {
    final fs = defaultTargetPlatform == TargetPlatform.android ? 18.0 : 13.0;
    final iconSz = defaultTargetPlatform == TargetPlatform.android
        ? 20.0
        : 18.0;
    final validIds = nodes.map((n) => n.id).toSet();
    final value = (selectedId != null && validIds.contains(selectedId))
        ? selectedId!
        : autoValue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NuBLimeColors.border0),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: NuBLimeColors.bg2,
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: NuBLimeColors.text3,
            size: iconSz,
          ),
          style: TextStyle(color: NuBLimeColors.text0, fontSize: fs),
          items: [
            DropdownMenuItem(
              value: autoValue,
              child: Text(isZh ? '⚡ 自动优选' : '⚡ Auto · Optimal'),
            ),
            ...nodes.map(
              (n) => DropdownMenuItem(
                value: n.id,
                child: Text(
                  '${n.flag} ${n.country}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            final picked = v == autoValue ? null : v;
            debugPrint('[NODE-PICKER] picked=$v selected=$selectedId');
            Logger.bootstrap.info(
              '[NODE-PICKER] picked=${v == autoValue ? "auto" : v} '
              'previous=${selectedId ?? "auto"}',
            );
            if (picked != selectedId) onChanged(picked);
          },
        ),
      ),
    );
  }
}

// ═══ 单节点版 — 静态智能优选占位 ═══
class _CountryLabel extends StatelessWidget {
  final bool isZh;
  const _CountryLabel({required this.isZh});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NuBLimeColors.border0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, color: NuBLimeColors.lemon, size: 18),
          const SizedBox(width: 8),
          Text(
            isZh ? '智能优选节点' : 'Auto · Optimal',
            style: TextStyle(color: NuBLimeColors.text0, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ═══ 流量统计 ═══
class _TrafficStats extends HookConsumerWidget {
  final bool isZh;
  const _TrafficStats({required this.isZh});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsNotifierProvider).asData?.value;
    final upS = stats?.uplink.toInt().speed() ?? '-- KB/s';
    final dnS = stats?.downlink.toInt().speed() ?? '-- KB/s';
    final upT = stats?.uplinkTotal.toInt().size() ?? '-- MB';
    final dnT = stats?.downlinkTotal.toInt().size() ?? '-- MB';
    final vfs = defaultTargetPlatform == TargetPlatform.android ? 18.0 : 14.0;
    final lfs = defaultTargetPlatform == TargetPlatform.android ? 18.0 : 12.0;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NuBLimeColors.border0),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _s(
                Icons.arrow_upward,
                isZh ? '↑ 上传' : '↑ UP',
                upS,
                NuBLimeColors.connected,
              ),
              const SizedBox(width: 8),
              _s(
                Icons.arrow_downward,
                isZh ? '↓ 下载' : '↓ DOWN',
                dnS,
                NuBLimeColors.connecting,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _s(
                Icons.cloud_upload_outlined,
                isZh ? '已上传' : 'Uploaded',
                upT,
                NuBLimeColors.text3,
              ),
              const SizedBox(width: 8),
              _s(
                Icons.cloud_download_outlined,
                isZh ? '已下载' : 'Downloaded',
                dnT,
                NuBLimeColors.text3,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _s(IconData i, String l, String v, Color c) {
    final vfs = defaultTargetPlatform == TargetPlatform.android ? 18.0 : 14.0;
    final lfs = defaultTargetPlatform == TargetPlatform.android ? 18.0 : 12.0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: NuBLimeColors.bg0,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(i, size: 14, color: c),
            const SizedBox(height: 2),
            Text(
              v,
              style: TextStyle(
                color: NuBLimeColors.text0,
                fontSize: vfs,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              l,
              style: TextStyle(
                color: NuBLimeColors.text1,
                fontSize: lfs,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══ 汉堡菜单 ═══
class _HamburgerMenu extends StatefulWidget {
  final WidgetRef ref;
  const _HamburgerMenu({required this.ref});

  @override
  State<_HamburgerMenu> createState() => _HamburgerMenuState();
}

class _HamburgerMenuState extends State<_HamburgerMenu> {
  /// VPN 功能默认收起：3 个子项只有点开才出现，避免主菜单一屏塞满。
  bool _vpnOpen = false;

  /// 「关于」分组（关于/隐私政策/服务条款/退款政策）同样默认收起。
  bool _aboutOpen = false;

  @override
  Widget build(BuildContext context) {
    final ref = widget.ref;
    final isZh = ref.watch(localePreferencesProvider).languageCode == 'zh';
    return SafeArea(
      // 菜单项变多后（VPN 功能三项 + 关于/政策），小屏 Drawer 高度不够会溢出。
      // 允许滚动，正常屏幕下表现不变（内容不超出时不会出现滚动条）。
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          _m(Icons.account_circle, isZh ? '账户信息' : 'Account', () {
            Navigator.pop(context);
            _push(context, const T65AccountPage());
          }),
          _m(Icons.devices, isZh ? '设备管理' : 'Devices', () {
            Navigator.pop(context);
            _push(context, const T61DevicesPage());
          }),
          _m(Icons.email_outlined, isZh ? '关联邮件地址' : 'Link Email', () {
            Navigator.pop(context);
            _push(context, const WildLimeBindEmailPage());
          }),
          _m(Icons.share, isZh ? '推荐给好友' : 'Refer a Friend', () {
            Navigator.pop(context);
            _push(context, const ReferralPage());
          }),
          const Divider(color: Colors.white12, height: 1),
          // 折叠分组：标题本身就是一个普通菜单项（同样的字号/颜色/行高），
          // 点一下展开三项，再点收起。默认收起，保持主菜单原有长度。
          _m(
            Icons.shield_outlined,
            isZh ? 'VPN 功能' : 'VPN Features',
            () => setState(() => _vpnOpen = !_vpnOpen),
            trailing: Icon(
              _vpnOpen ? Icons.expand_less : Icons.expand_more,
              color: Colors.white54,
              size: 20,
            ),
          ),
          if (_vpnOpen) ...[
            _m(Icons.security_outlined, isZh ? '断网保护' : 'Kill Switch', () {
              Navigator.pop(context);
              _push(context, const KillSwitchPage());
            }, indent: 16),
            _m(Icons.verified_user_outlined,
                isZh ? '加强保护设置' : 'Enhanced Protection', () {
              Navigator.pop(context);
              ref.read(dialogNotifierProvider.notifier).showLockdownGuide();
            }, indent: 16),
            _m(Icons.apps_outlined, isZh ? '分应用代理' : 'Per-App Proxy', () {
              Navigator.pop(context);
              _push(context, const PerAppProxyEntryPage());
            }, indent: 16),
          ],
          const Divider(color: Colors.white12, height: 1),
          _m(
            Icons.language,
            isZh ? '系统语言' : 'Language',
            () => _lang(ref, context),
          ),
          // 「关于」同样是折叠分组：与「VPN 功能」一套样式，默认收起。
          _m(
            Icons.info_outline,
            isZh ? '关于' : 'About',
            () => setState(() => _aboutOpen = !_aboutOpen),
            trailing: Icon(
              _aboutOpen ? Icons.expand_less : Icons.expand_more,
              color: Colors.white54,
              size: 20,
            ),
          ),
          if (_aboutOpen) ...[
            _m(Icons.info_outline, isZh ? '关于 WildLime VPN' : 'About WildLime VPN', () {
              Navigator.pop(context);
              _push(context, const AboutPage());
            }, indent: 16),
            _m(Icons.privacy_tip_outlined, isZh ? '隐私政策' : 'Privacy Policy', () {
              Navigator.pop(context);
              _launch(Constants.privacyPolicyUrl);
            }, indent: 16),
            _m(
              Icons.description_outlined,
              isZh ? '服务条款' : 'Terms of Service',
              () {
                Navigator.pop(context);
                _launch(Constants.termsAndConditionsUrl);
              },
              indent: 16,
            ),
            _m(Icons.money_off, isZh ? '退款政策' : 'Refund Policy', () {
              Navigator.pop(context);
              _launch('https://nublime.com/refund/');
            }, indent: 16),
          ],
          const Divider(color: Colors.white12, height: 1),
          _m(Icons.logout, isZh ? '退出登录' : 'Sign Out', () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: NuBLimeColors.bg2,
                title: Text(
                  isZh ? '确认退出' : 'Sign Out',
                  style: TextStyle(color: NuBLimeColors.text0),
                ),
                content: Text(
                  isZh ? '退出后需要重新输入激活码才能使用VPN。' : 'You will need to re-enter your activation code.',
                  style: TextStyle(color: NuBLimeColors.text1),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(isZh ? '取消' : 'Cancel',
                        style: TextStyle(color: NuBLimeColors.text2)),
                  ),
                  TextButton(
                    onPressed: () async {
                      // 两个坑（2026-10-31 真机）：
                      // 1) 抽屉一关 context 就失效，之后 context.go 抛「deactivated widget」；
                      // 2) Preferences.introCompleted 的 provider 在 sharedPreferences 仍是
                      //    AsyncLoading 时创建，会在 requireValue 处抛 Bad state，异常把整个
                      //    handler 打断 —— 表现就是点了「退出」毫无反应。所以直接写 prefs。
                      final router = ref.read(goRouterNotiferProvider);
                      Navigator.pop(ctx);
                      try {
                        await AuthTokenStorage().clearToken();
                        final sp = await ref.read(sharedPreferencesProvider.future);
                        await sp.setBool('intro_completed', false);
                        try { ref.invalidate(Preferences.introCompleted); } catch (_) {}
                        if (context.mounted) Navigator.pop(context);
                        router.go('/intro');
                        router.refresh();
                      } catch (e, st) {
                        debugPrint('[LOGOUT] failed: $e\n$st');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(isZh ? '退出失败：$e' : 'Sign out failed: $e')),
                          );
                        }
                      }
                    },
                    child: Text(isZh ? '退出' : 'Sign Out',
                        style: TextStyle(color: NuBLimeColors.error)),
                  ),
                ],
              ),
            );
          }, red: true),
          _m(Icons.exit_to_app, isZh ? '退出应用' : 'Exit App', () {
            if (ref.read(connectionNotifierProvider).valueOrNull?.isConnected ==
                true)
              ref.read(connectionNotifierProvider.notifier).toggleConnection();
            SystemNavigator.pop();
          }, red: true),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white10,
              ),
              child: const Icon(Icons.close, color: Colors.white54, size: 22),
            ),
          ),
          const SizedBox(height: 20),
        ],
        ),
      ),
    );
  }

  Widget _m(IconData i, String t, VoidCallback o,
          {bool red = false, Widget? trailing, double indent = 0}) =>
      Padding(
        padding: EdgeInsets.only(left: indent),
        child: ListTile(
          leading: Icon(
            i,
            color: red ? Colors.redAccent : Colors.white70,
            size: 22,
          ),
          title: Text(
            t,
            style: TextStyle(
              color: red ? Colors.redAccent : Colors.white,
              fontSize: 15,
            ),
          ),
          trailing: trailing,
          onTap: o,
          dense: true,
        ),
      );
  void _push(BuildContext ctx, Widget page) {
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => page));
  }

  void _launch(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _lang(WidgetRef ref, BuildContext ctx) {
    // 语言选择前不关闭 drawer — 避免闪退
    showDialog(
      context: ctx,
      builder: (d) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          '语言 / Language',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                '中文',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                ref.read(localePreferencesProvider.notifier).setLocale('zh');
                Navigator.of(d).pop();
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              title: const Text(
                'English',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                ref.read(localePreferencesProvider.notifier).setLocale('en');
                Navigator.of(d).pop();
                Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
