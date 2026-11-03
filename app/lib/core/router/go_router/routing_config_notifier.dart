// lib/core/router/go_router/routing_config_notifier.dart
import 'package:flutter/material.dart';
import 'package:nublime/core/auth/t59_auth_token_storage.dart';
import 'package:nublime/core/auth/preloaded_auth_token_provider.dart';
import 'package:nublime/core/logger/logger.dart';
import 'package:go_router/go_router.dart';
import 'package:nublime/core/preferences/general_preferences.dart';
import 'package:nublime/core/preferences/preferences_provider.dart';
import 'package:nublime/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:nublime/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:nublime/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:nublime/core/router/go_router/helper/custom_transition.dart';
import 'package:nublime/core/router/go_router/refresh_listenable.dart';
import 'package:nublime/features/about/widget/about_page.dart';
import 'package:nublime/features/home/wildlime_home_page.dart';
import 'package:nublime/features/log/overview/logs_page.dart';
import 'package:nublime/features/per_app_proxy/overview/per_app_proxy_page.dart';
import 'package:nublime/features/profile/details/profile_details_page.dart';
import 'package:nublime/features/profile/notifier/active_profile_notifier.dart';
import 'package:nublime/features/profile/overview/profiles_page.dart';
import 'package:nublime/features/proxy/overview/proxies_overview_page.dart';
import 'package:nublime/features/settings/overview/sections/dns_options_page.dart';
import 'package:nublime/features/settings/overview/sections/general_page.dart';
import 'package:nublime/features/settings/overview/sections/inbound_options_page.dart';
import 'package:nublime/features/settings/overview/sections/route_options_page.dart';
import 'package:nublime/features/settings/overview/sections/tls_tricks_page.dart';
import 'package:nublime/features/onboarding/t60_activation_page.dart';
import 'package:nublime/features/settings/t62_settings_page.dart';
import 'package:nublime/features/stats/widget/stats_page.dart';
import 'package:nublime/features/devices/t61_devices_page.dart';
import 'package:nublime/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'routing_config_notifier.g.dart';

// each branch in go router has its own focus scope
final branchesScope = <String, FocusScopeNode>{
  'home': FocusScopeNode(),
  'stats': FocusScopeNode(),
  'devices': FocusScopeNode(),
  'settings': FocusScopeNode(),
  'profiles': FocusScopeNode(),
  'logs': FocusScopeNode(),
  'about': FocusScopeNode(),
};

// when the routing config is not yet initialized, this config is used
final loadingConfig = RoutingConfig(
  routes: <RouteBase>[
    GoRoute(
      path: '/home',
      builder: (context, state) => const Scaffold(
        backgroundColor: Color(0xFF060C18),
        body: SizedBox.shrink(),
      ),
    ),
  ],
);

String getNameOfBranch(bool isMobileBreakpoint, bool showProfilesAction, int index) =>
    isMobileBreakpoint
        ? ['home', 'stats', 'devices', 'settings'][index]
        : ['home', if (showProfilesAction) 'profiles', 'settings', 'logs', 'about'][index];

int getIndexOfBranch(bool isMobileBreakpoint, bool showProfilesAction, String name) =>
    isMobileBreakpoint
        ? ['home', 'stats', 'devices', 'settings'].indexOf(name)
        : ['home', if (showProfilesAction) 'profiles', 'settings', 'logs', 'about'].indexOf(name);

@Riverpod(keepAlive: true)
class RoutingConfigNotifier extends _$RoutingConfigNotifier {
  @override
  RoutingConfig build() {
    // Ensure preferences are loaded before building real routing config
    final prefsReady = ref.watch(sharedPreferencesProvider).valueOrNull;
    final tokenPreload = ref.watch(preloadedAuthTokenProvider);
    final isMobileBreakpoint = ref.watch(isMobileBreakpointProvider);
    final bool showProfilesAction;
    if (isMobileBreakpoint == true) {
      showProfilesAction = false;
    } else {
      showProfilesAction = ref.watch(hasAnyProfileProvider).value ?? false;
    }
    if (isMobileBreakpoint == null || prefsReady == null || !tokenPreload.loaded) {
      Logger.bootstrap.info('[ROUTER-BUILD] returning loadingConfig '
          'isMobile=$isMobileBreakpoint prefsReady=$prefsReady tokenLoaded=${tokenPreload.loaded}');
      return loadingConfig;
    }
    Logger.bootstrap.info('[ROUTER-BUILD] returning REAL config '
        'isMobile=$isMobileBreakpoint prefsReady=$prefsReady tokenLoaded=${tokenPreload.loaded}');

    return RoutingConfig(
      redirect: (context, state) async {
        bool introCompleted;
        try {
          introCompleted = ref.read(Preferences.introCompleted);
        } catch (_) {
          return null;
        }
        final isIntro = state.matchedLocation == '/intro';

        String? url;
        if (LinkParser.protocols.contains(state.uri.scheme)) {
          url = state.uri.toString();
        } else if (PlatformUtils.isDesktop && newUrlFromAppLink.isNotEmpty) {
          url = newUrlFromAppLink;
          newUrlFromAppLink = '';
        } else if (state.uri.queryParameters['url'] != null) {
          url = state.uri.queryParameters['url'];
        }

        // 启动顺序：splash → 激活码 → 主页。移除 token-valid 旁路，
        // 仅以 Preferences.introCompleted 作为是否已激活的唯一依据。
        Logger.bootstrap.info('[REDIRECT] loc=${state.matchedLocation} '
            'intro=$introCompleted tokenLoaded=${tokenPreload.loaded} '
            'tokenValid=${tokenPreload.token?.isValid}');

        if (!introCompleted) {
          if (isIntro) return null;
          return url != null ? '/intro?url=$url' : '/intro';
        }

        // APEX V5: 同步检查 profile（不 await，避免阻塞 redirect）
        if (!isIntro) {
          try {
            final state = ref.read(activeProfileProvider);
            if (state case AsyncData(value: null)) {
              return '/intro';
            }
          } catch (_) {}
        }

        if (isIntro) {
          if (url != null) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(url: url),
            );
          }
          return '/home';
        } else if (url != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(url: url),
          );
          return '/home';
        }
        return null;
      },
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) => MyAdaptiveLayout(
            navigationShell: navigationShell,
            isMobileBreakpoint: isMobileBreakpoint,
            showProfilesAction: showProfilesAction,
          ),
          branches: <StatefulShellBranch>[
            // Branch 0: Home
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'home',
                  path: '/home',
                  builder: (_, _) => FocusScope(
                    node: branchesScope['home'],
                    child: const WildLimeHomePage(),
                  ),
                  routes: <GoRoute>[
                    GoRoute(
                      name: 'proxies',
                      path: '/proxies',
                      pageBuilder: (_, state) =>
                          customTransition(TransitionType.fade, state.pageKey, const ProxiesOverviewPage()),
                    ),
                    if (isMobileBreakpoint)
                      GoRoute(
                        name: 'profileDetails',
                        path: '/profile-details/:id',
                        pageBuilder: (_, state) => customTransition(
                          TransitionType.fade,
                          state.pageKey,
                          ProfileDetailsPage(id: state.pathParameters['id']!),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Branch 1: Stats (mobile only)
            if (isMobileBreakpoint)
              StatefulShellBranch(
                routes: <GoRoute>[
                  GoRoute(
                    name: 'stats',
                    path: '/stats',
                    builder: (_, _) => FocusScope(
                      node: branchesScope['stats'],
                      child: const StatsPage(),
                    ),
                  ),
                ],
              ),

            // Branch 2: Devices (mobile only)
            if (isMobileBreakpoint)
              StatefulShellBranch(
                routes: <GoRoute>[
                  GoRoute(
                    name: 'devices',
                    path: '/devices',
                    builder: (_, _) => FocusScope(
                      node: branchesScope['devices'],
                      child: const T61DevicesPage(),
                    ),
                  ),
                ],
              ),

            // Desktop: profiles branch
            if (showProfilesAction && !isMobileBreakpoint)
              StatefulShellBranch(
                routes: <GoRoute>[
                  GoRoute(
                    name: 'profiles',
                    path: '/profiles',
                    builder: (_, _) => FocusScope(node: branchesScope['profiles'], child: const ProfilesPage()),
                    routes: <GoRoute>[
                      GoRoute(
                        name: 'profileDetails',
                        path: '/profiles/:id',
                        pageBuilder: (_, state) => customTransition(
                          TransitionType.fade,
                          state.pageKey,
                          ProfileDetailsPage(id: state.pathParameters['id']!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

            // Settings branch
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'settings',
                  path: '/settings',
                  builder: (context, _) => FocusScope(
                    node: branchesScope['settings'],
                    child: PopScope(
                      canPop: false,
                      onPopInvokedWithResult: (_, _) => context.goNamed('home'),
                      child: const T62SettingsPage(),
                    ),
                  ),
                  routes: <GoRoute>[
                    GoRoute(
                      name: 'general',
                      path: '/general',
                      pageBuilder: (_, state) =>
                          customTransition(TransitionType.slide, state.pageKey, const GeneralPage()),
                    ),
                    GoRoute(
                      name: 'routeOptions',
                      path: '/route-options',
                      pageBuilder: (_, state) =>
                          customTransition(TransitionType.slide, state.pageKey, const RouteOptionsPage()),
                      routes: <GoRoute>[
                        GoRoute(
                          name: 'perAppProxy',
                          path: '/per-app-proxy',
                          pageBuilder: (_, state) =>
                              customTransition(TransitionType.slide, state.pageKey, const PerAppProxyPage()),
                        ),
                      ],
                    ),
                    GoRoute(
                      name: 'dnsOptions',
                      path: '/dns-options',
                      pageBuilder: (_, state) =>
                          customTransition(TransitionType.slide, state.pageKey, const DnsOptionsPage()),
                    ),
                    GoRoute(
                      name: 'inboundOptions',
                      path: '/inbound-options',
                      pageBuilder: (_, state) =>
                          customTransition(TransitionType.slide, state.pageKey, const InboundOptionsPage()),
                    ),
                    GoRoute(
                      name: 'tlsTricks',
                      path: '/tls-tricks',
                      pageBuilder: (_, state) =>
                          customTransition(TransitionType.slide, state.pageKey, const TlsTricksPage()),
                    ),
                    if (isMobileBreakpoint) ...[
                      GoRoute(
                        name: 'logs',
                        path: '/logs',
                        pageBuilder: (_, state) =>
                            customTransition(TransitionType.slide, state.pageKey, const LogsPage()),
                      ),
                      GoRoute(
                        name: 'about',
                        path: '/about',
                        pageBuilder: (_, state) =>
                            customTransition(TransitionType.slide, state.pageKey, const AboutPage()),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            // Desktop only branches
            if (!isMobileBreakpoint) ...[
              StatefulShellBranch(
                routes: <GoRoute>[
                  GoRoute(
                    name: 'logs',
                    path: '/logs',
                    builder: (_, _) => FocusScope(node: branchesScope['logs'], child: const LogsPage()),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: <GoRoute>[
                  GoRoute(
                    name: 'about',
                    path: '/about',
                    builder: (_, _) => FocusScope(node: branchesScope['about'], child: const AboutPage()),
                  ),
                ],
              ),
            ],
          ],
        ),

        // Intro / Activation page
        GoRoute(
          name: 'intro',
          path: '/intro',
          builder: (_, _) => const T60ActivationPage(),
        ),
      ],
    );
  }
}
