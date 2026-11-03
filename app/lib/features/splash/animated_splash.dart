// lib/features/splash/animated_splash.dart
// WildLime VPN — Animated Lemon Logo Splash Screen (v3 — audit fix)
//
// 关键修复：
// 1. 移除 Scaffold —— 此处位于 MaterialApp 之上，没有 MediaQuery 祖先，
//    Scaffold.build 会抛 "No MediaQuery widget ancestor found"，release 下
//    被静默替换为空白 ErrorWidget（即旧版"黑屏"的真正来源）。
// 2. widget.child 自首帧起无条件挂载于 Stack 底层：GoRouter redirect、
//    路由解析、首页 build 全部在不透明遮罩下完成（预热），淡出即无缝。
// 3. _done 后保持 Stack 结构不变，仅移除遮罩 —— 避免 child 被重新挂载
//    导致整个 App State 重建。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';

class AnimatedSplash extends StatefulWidget {
  final Widget child;
  final Future<void> ready;

  const AnimatedSplash({super.key, required this.child, required this.ready});

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends State<AnimatedSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _minTimePassed = false;
  bool _appReady = false;
  bool _fading = false;
  bool _done = false;
  bool _precached = false;

  /// splash 最短展示时长（颜色过渡动画可见时间 = 1500ms + 额外 1s 体感）
  static const _minDisplay = Duration(milliseconds: 2500);
  static const _fadeDuration = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    debugPrint('[SPLASH] visible');

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: NuBLimeColors.bg0,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    Future.delayed(_minDisplay, () {
      if (!mounted) return;
      setState(() => _minTimePassed = true);
      _maybeStartFade();
    });

    widget.ready.then(
      (_) => _onReady(),
      onError: (Object e, StackTrace st) {
        // bootstrap 失败也必须放行，绝不让用户卡死在 splash
        debugPrint('[SPLASH] ready completed with error: $e');
        _onReady();
      },
    );
  }

  void _onReady() {
    if (!mounted) return;
    debugPrint('[SPLASH] app ready');
    setState(() => _appReady = true);
    _maybeStartFade();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      // 预解码，保证首帧 logo 即可见
      precacheImage(const AssetImage('assets/icon/nublime_512x512.png'), context);
      precacheImage(const AssetImage('assets/icon/nublime_red_512x512.png'), context);
    }
  }

  void _maybeStartFade() {
    if (!_minTimePassed || !_appReady || _fading || _done) return;
    debugPrint('[SPLASH] fade start');
    setState(() => _fading = true);
    // 注意：淡出期间 _ctrl 继续运行，动画不冻结；fade 完成后再 stop。
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ① App 自首帧起常驻底层：在遮罩下完成 GoRouter 预热与首页渲染。
          //    树形结构在整个生命周期内不变 → App State 永不丢失。
          widget.child,

          // ② 不透明 splash 遮罩；_done 后整体移除（child 位置不受影响）。
          if (!_done)
            Positioned.fill(
              child: IgnorePointer(
                // 淡出期间不拦截下层点击
                ignoring: _fading,
                child: AnimatedOpacity(
                  opacity: _fading ? 0.0 : 1.0,
                  duration: _fadeDuration,
                  curve: Curves.easeOut,
                  onEnd: () {
                    if (mounted && _fading) {
                      debugPrint('[SPLASH] fade complete');
                      _ctrl.stop();
                      setState(() => _done = true);
                    }
                  },
                  // ③ 核心修复：用 ColoredBox 替代 Scaffold。
                  //    此层无 MaterialApp/MediaQuery 祖先，Scaffold 必抛异常。
                  child: ColoredBox(
                    color: NuBLimeColors.bg0,
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _ctrl,
                        builder: (context, _) {
                          final v = _ctrl.value;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.scale(
                                scale: 0.92 + v * 0.16,
                                child: ClipOval(
                                  child: Container(
                                    width: 180,
                                    height: 180,
                                    color: NuBLimeColors.bg0,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Opacity(
                                          opacity: (1.0 - v).clamp(0.0, 1.0),
                                          child: Image.asset(
                                            'assets/icon/nublime_512x512.png',
                                            width: 170, height: 170,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        Opacity(
                                          opacity: v.clamp(0.0, 1.0),
                                          child: Image.asset(
                                            'assets/icon/nublime_red_512x512.png',
                                            width: 170, height: 170,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text('野柠檬 VPN',
                                  style: TextStyle(
                                      color: NuBLimeColors.text0,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 4.0)),
                              const SizedBox(height: 8),
                              const Text('WildLime VPN',
                                  style: TextStyle(
                                      color: NuBLimeColors.lemon,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.5)),
                              const SizedBox(height: 12),
                              const Text('Secure · Fast · Private',
                                  style: TextStyle(
                                      color: NuBLimeColors.text2,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 2.0)),
                              const SizedBox(height: 40),
                              _Dots(ctrl: _ctrl),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final AnimationController ctrl;
  const _Dots({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final v = ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final d = ((v + index * 0.2) % 1.0).clamp(0.0, 1.0);
            final e = Curves.easeInOut
                .transform((d < 0.5 ? d * 2 : (1.0 - d) * 2).clamp(0.0, 1.0));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NuBLimeColors.lemon.withValues(alpha: 0.2 + e * 0.6),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
