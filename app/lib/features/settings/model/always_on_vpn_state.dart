import 'package:flutter/services.dart';

/// 系统级断网保护（Always-on VPN + 阻止无 VPN 连接）的真实状态。
///
/// 这个状态只能从系统读到，App 自己无法伪造：
/// - `Settings.Secure.always_on_vpn_app` 记录哪个包是系统级 VPN
/// - `Settings.Secure.always_on_vpn_lockdown` 记录是否开启「阻止无 VPN 连接」
///
/// 两者都命中才是真正的 fail-closed 保护；只命中前者时 VPN 挂掉系统会尝试重连，
/// 但不会阻断流量。
enum AlwaysOnVpnStatus {
  /// 本应用是系统级 VPN，且已开启 lockdown —— VPN 不在时全部流量被阻断。
  enabled,

  /// 本应用是系统级 VPN，但未开启 lockdown —— 断线仍可能短暂泄漏。
  partial,

  /// 本应用不是系统级 VPN。
  disabled,

  /// 读不到系统设置（非 Android 平台，或 ROM 屏蔽了该键）。
  unknown,
}

class AlwaysOnVpnState {
  final bool supported;
  final String? alwaysOnApp;
  final bool isThisApp;
  final bool lockdown;
  final String? error;

  const AlwaysOnVpnState({
    required this.supported,
    this.alwaysOnApp,
    this.isThisApp = false,
    this.lockdown = false,
    this.error,
  });

  const AlwaysOnVpnState.unknown([String? error])
      : supported = false,
        alwaysOnApp = null,
        isThisApp = false,
        lockdown = false,
        error = error;

  /// 解析 MethodChannel 返回的 map。任何形状错误都退化为 unknown，
  /// 绝不把「没读到」当成「已开启」。
  factory AlwaysOnVpnState.fromChannelValue(dynamic raw) {
    if (raw is! Map) return const AlwaysOnVpnState.unknown('unexpected payload');
    final supported = raw['supported'] == true;
    if (!supported) {
      return AlwaysOnVpnState.unknown(raw['error']?.toString());
    }
    final app = raw['alwaysOnApp'];
    return AlwaysOnVpnState(
      supported: true,
      alwaysOnApp: app is String ? app : null,
      isThisApp: raw['isThisApp'] == true,
      lockdown: raw['lockdown'] == true,
    );
  }

  AlwaysOnVpnStatus get status {
    if (!supported) return AlwaysOnVpnStatus.unknown;
    if (isThisApp && lockdown) return AlwaysOnVpnStatus.enabled;
    if (isThisApp) return AlwaysOnVpnStatus.partial;
    return AlwaysOnVpnStatus.disabled;
  }

  bool get isProtected => status == AlwaysOnVpnStatus.enabled;
}

/// 读写系统级断网保护状态的唯一入口。
class AlwaysOnVpnService {
  const AlwaysOnVpnService();

  static const MethodChannel _channel = MethodChannel('com.nublime.app/method');

  /// 读取真实状态。任何异常都返回 unknown，由 UI 如实展示"无法检测"。
  Future<AlwaysOnVpnState> read() async {
    try {
      final value = await _channel.invokeMethod<dynamic>('getAlwaysOnVpnState');
      return AlwaysOnVpnState.fromChannelValue(value);
    } on MissingPluginException {
      return const AlwaysOnVpnState.unknown('not supported on this platform');
    } on PlatformException catch (e) {
      return AlwaysOnVpnState.unknown(e.message ?? e.code);
    } catch (e) {
      return AlwaysOnVpnState.unknown(e.toString());
    }
  }

  /// 打开系统 VPN 设置页，让用户把本应用设为「始终开启」并开「阻止无 VPN 连接」。
  Future<bool> openSystemVpnSettings() async {
    try {
      final ok = await _channel.invokeMethod<bool>('openVpnSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
