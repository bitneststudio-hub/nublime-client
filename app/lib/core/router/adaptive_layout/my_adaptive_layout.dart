// lib/core/router/adaptive_layout/my_adaptive_layout.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:nublime/core/model/constants.dart';
import 'package:nublime/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:nublime/core/router/go_router/routing_config_notifier.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MyAdaptiveLayout extends HookConsumerWidget {
  const MyAdaptiveLayout({
    super.key,
    required this.navigationShell,
    required this.isMobileBreakpoint,
    required this.showProfilesAction,
  });

  final StatefulNavigationShell navigationShell;
  final bool isMobileBreakpoint;
  final bool showProfilesAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryFocusHash = useState<int?>(null);
    final navScopeNode = useFocusScopeNode();

    useEffect(() {
      bool handler(KeyEvent event) {
        final arrows = isMobileBreakpoint
            ? KeyboardConst.verticalArrows
            : KeyboardConst.horizontalArrows;
        if (!arrows.contains(event.logicalKey)) return false;
        if (event is KeyDownEvent) {
          primaryFocusHash.value = FocusManager.instance.primaryFocus.hashCode;
        } else {
          if (primaryFocusHash.value == FocusManager.instance.primaryFocus.hashCode) {
            if (branchesScope.values.any((node) => node.hasFocus)) {
              navScopeNode.requestFocus();
            } else if (navScopeNode.hasFocus) {
              branchesScope[getNameOfBranch(isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex)]
                  ?.requestFocus();
            }
          }
        }
        return true;
      }
      HardwareKeyboard.instance.addHandler(handler);
      return () => HardwareKeyboard.instance.removeHandler(handler);
    }, [isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex]);

    if (isMobileBreakpoint) {
      return _buildMobileLayout(context, navScopeNode);
    } else {
      return _buildDesktopLayout(context, navScopeNode);
    }
  }

  // Mobile: NuBLime 自定义底部导航（主页/统计/设备/设置）
  Widget _buildMobileLayout(BuildContext context, FocusScopeNode navScopeNode) {
    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      body: navigationShell,
      bottomNavigationBar: const SizedBox.shrink(), // WildLime: 隐藏底部导航
    );
  }

  // Desktop: No sidebar — WildLime uses compact single-page layout
  Widget _buildDesktopLayout(BuildContext context, FocusScopeNode navScopeNode) {
    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      body: navigationShell,
    );
  }

  List<NavigationRailDestination> _desktopDests() => [
    NavigationRailDestination(icon: Icon(Icons.home_outlined), label: Text('主页')),
    if (showProfilesAction)
      NavigationRailDestination(icon: Icon(Icons.view_list_outlined), label: Text('配置')),
    NavigationRailDestination(icon: Icon(Icons.settings_outlined), label: Text('设置')),
    NavigationRailDestination(icon: Icon(Icons.description_outlined), label: Text('日志')),
    NavigationRailDestination(icon: Icon(Icons.info_outlined), label: Text('关于')),
  ];

  void _onTap(BuildContext context, int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }
}

class _NavTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavTab({required this.icon, required this.activeIcon, required this.label});
}
