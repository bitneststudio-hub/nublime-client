import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nublime/core/auth/preloaded_auth_token_provider.dart';
import 'package:nublime/core/preferences/general_preferences.dart';
import 'package:nublime/core/preferences/preferences_provider.dart';
import 'package:nublime/core/router/go_router/refresh_listenable.dart';
import 'package:nublime/core/router/go_router/routing_config_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'go_router_notifier.g.dart';

// if 'stateful shell route' navigators not registered, this navigator key can be used for showing dialog or bottom sheet...
final rootNavKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');

@Riverpod(keepAlive: true)
class GoRouterNotifer extends _$GoRouterNotifer {
  static final rConfig = ValueNotifier<RoutingConfig>(loadingConfig);
  @override
  GoRouter build() {
    final router = GoRouter.routingConfig(
      initialLocation: '/home',
      navigatorKey: rootNavKey,
      routingConfig: rConfig,
      refreshListenable: RefreshListenable(ref),
      errorBuilder: (context, state) {
        debugPrint('[ROUTER-ERROR] uri=${state.uri} error=${state.error}');
        if (kDebugMode) {
          return Material(
            color: const Color(0xFF060C18),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Route error\n${state.uri}\n${state.error}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            ),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => context.goNamed('home'));
        return const Material(color: Color(0xFF060C18));
      },
    );
    ref.listen(routingConfigNotifierProvider, (_, next) {
      rConfig.value = next;
      // GoRouter 16.x 的 routingConfig 切换只 reparse 当前路由，不会重新跑
      // topRedirect。我们必须手动 navigate 到 redirect 应该去的位置，否则
      // 用户从 loadingConfig 期间渲染出的 /home 永远不会被 redirect 到 /intro。
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final currentUri = router.routerDelegate.currentConfiguration.uri;
        final onIntro = currentUri.path == '/intro';
        // 同步从 SharedPreferences 读 intro_completed，避免触发
        // PreferencesNotifier 的 build（其构造同步 requireValue 会因
        // sharedPreferencesProvider 状态机问题抛错）。
        bool introCompleted = false;
        try {
          final sp = ref.read(sharedPreferencesProvider).valueOrNull;
          if (sp != null) {
            introCompleted = sp.getBool('intro_completed') ?? false;
          } else {
            // 下一帧再读
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final sp2 = ref.read(sharedPreferencesProvider).valueOrNull;
              final v = sp2?.getBool('intro_completed') ?? false;
              debugPrint('[ROUTER-NAVI] retry sp2=$v onIntro=$onIntro');
              _navigate(router, ref, onIntro: onIntro, introCompleted: v);
            });
            return;
          }
        } catch (e) {
          debugPrint('[ROUTER-NAVI] read shared prefs threw: $e');
        }
        debugPrint('[ROUTER-NAVI] currentUri=${currentUri.path} '
            'onIntro=$onIntro introCompleted=$introCompleted');
        _navigate(router, ref, onIntro: onIntro, introCompleted: introCompleted);
      });
      router.refresh();
    });
    return router;
  }
}

void _navigate(
  GoRouter router,
  Ref ref, {
  required bool onIntro,
  required bool introCompleted,
}) {
  if (onIntro) return;
  if (!introCompleted) {
    router.go('/intro');
  } else {
    // intro 已完成但当前在 /home 占位页（loadingConfig 的 builder 是
    // SizedBox.shrink），且 profile 已就绪：goNamed('home') 会触发重新
    // 渲染真实 home 页面。
    try {
      final tokenLoaded = ref.read(preloadedAuthTokenProvider).loaded;
      if (tokenLoaded) {
        router.goNamed('home');
      }
    } catch (_) {}
  }
}
