import 'package:nublime/nublimecore/model/core_types.dart';
import 'package:nublime/nublimecore/model/route_rule.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nublime/core/preferences/actions_at_closing.dart';
import 'package:nublime/utils/custom_loggers.dart';
import 'package:nublime/core/localization/locale_preferences.dart';
import 'package:nublime/core/preferences/general_preferences.dart';
import 'package:nublime/core/router/dialog/widgets/action_at_closing_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/confirmation_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/custom_alert_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/experimental_feature_notice.dart';
import 'package:nublime/core/router/dialog/widgets/free_profile_consent_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/help_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/new_version_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/no_active_profile_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/ok_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/proxy_info_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/save_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/setting_checkbox_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/setting_input_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/setting_picker_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/setting_radio_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/setting_slider_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/setting_text_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/sort_profiles_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/unknown_domains_warning_dialog.dart';
import 'package:nublime/core/router/dialog/widgets/window_closing_dialog.dart';
import 'package:nublime/core/router/go_router/go_router_notifier.dart';
import 'package:nublime/features/app_update/model/remote_version_entity.dart';
import 'package:nublime/features/common/qr_code_dialog.dart';
import 'package:nublime/features/common/qr_code_scanner_screen.dart';
import 'package:nublime/features/settings/data/config_option_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dialog_notifier.g.dart';

@Riverpod(keepAlive: true)
class DialogNotifier extends _$DialogNotifier {
  @override
  void build() {}

  Future<T?> _show<T>(Widget child) async {
    final context = rootNavKey.currentContext;
    // R01 §7 (C-1): runtime failures are reported through this same path; log the outcome so a
    // missing dialog is distinguishable from an unlogged call (this replaces an inert print()).
    if (context == null) {
      state = AsyncError("[dialog] no root navigator context", StackTrace.current);
      return null;
    }
    // ref.read(popupCountNotifierProvider.notifier).increase();
    final pushed = await Navigator.of(context).push<T>(DialogRoute(context: context, builder: (context) => child)).then((
      value,
    ) {
      // ref.read(popupCountNotifierProvider.notifier).decrease();
      return value;
    });
    return pushed;
  }

  Future<String?> showQrScanner() async {
    return await _show<String?>(const QrCodeScannerDialog());
  }

  Future<void> showSortProfiles() async {
    return await _show<void>(const SortProfilesDialog());
  }


  Future<void> showQrCode(String link, {String? message}) async {
    return await _show<void>(QrCodeDialog(link, message: message));
  }

  Future<void> showOk(String title, String description) async {
    return await _show<void>(OkDialog(title: title, description: description));
  }

  Future<double?> showSettingSlider({
    required String title,
    required double initialValue,
    VoidCallback? onReset,
    double min = 0,
    double max = 1,
    int? divisions,
    String Function(double value)? labelGen,
  }) async {
    return await _show<double?>(
      SettingsSliderDialog(
        title: title,
        initialValue: initialValue,
        onReset: onReset,
        min: min,
        max: max,
        divisions: divisions,
        labelGen: labelGen,
      ),
    );
  }

  Future<void> showNewVersion({
    required String currentVersion,
    required RemoteVersionEntity newVersion,
    required bool canIgnore,
  }) async {
    return await _show<void>(NewVersionDialog(currentVersion, newVersion, canIgnore: canIgnore));
  }

  Future<bool> showConfirmation({
    required String title,
    required String message,
    IconData? icon,
    String? positiveBtnTxt,
  }) async {
    return await _show<bool>(
          ConfirmationDialog(title: title, message: message, icon: icon, positiveBtnTxt: positiveBtnTxt),
        ) ??
        false;
  }

  Future<ActionsAtClosing?> showActionAtClosing({required ActionsAtClosing selected}) async {
    return await _show<ActionsAtClosing?>(ActionsAtClosingDialog(selected: selected));
  }

  Future<bool> showExperimentalFeatureNotice() async {
    final hasExperimental = ref.read(ConfigOptions.hasExperimentalFeatures);
    final canShowNotice = !ref.read(disableExperimentalFeatureNoticeProvider);
    if (hasExperimental && canShowNotice) {
      return await _show<bool?>(const ExperimentalFeatureNoticeDialog()) ?? false;
    }
    return true;
  }

  Future<void> showNoActiveProfile() async {
    return await _show<void>(const NoActiveProfileDialog());
  }

  Future<void> showHelpDialog() async {
    return await _show<void>(const HelpDialog());
  }

  Future<bool> showFreeProfileConsent({required String title, required String consent}) async {
    return await _show<bool?>(FreeProfileConsentDialog(title: title, consent: consent)) ?? false;
  }

  Future<bool> showUnknownDomainsWarning({required String url}) async {
    return await _show<bool?>(UnknownDomainsWarningDialog(url: url)) ?? false;
  }

  /// 系统级加强保护引导（Always-on VPN + Lockdown）。
  /// 返回 true = 用户点了「去设置」（本方法内已完成跳转）。
  /// 调用点：① 首次 CONNECTED 自动弹（调用侧先置 lockdownGuideShown）
  ///        ② 设置页「加强保护设置」常驻入口。
  Future<void> showLockdownGuide() async {
    // 这个弹窗原来只有中文，切到英文后整段还是中文（按钮 "Cancel" 来自组件默认值，
    // 于是中英混排）。按当前语言取文案。
    final isZh = ref.read(localePreferencesProvider).languageCode == 'zh';
    final goSettings = await _show<bool>(
          ConfirmationDialog(
            title: isZh ? '加强保护（推荐开启）' : 'Enhanced protection (recommended)',
            message: isZh
                ? '连接已建立。建议开启系统级加强保护（Always-on VPN + 屏蔽未使用 VPN 的所有连接），'
                    '即使应用重启、断线重连，流量也不会意外走出隧道。\n\n'
                    '⚠️ 注意：开启「屏蔽未使用 VPN 的所有连接」后，手动断开 VPN 时手机会暂时没有网络连接，'
                    '直到重新连上——这是该设置本身的正常行为，不是故障。\n\n'
                    '跳转后请在 VPN 列表中找到 WildLime VPN，点右侧箭头进入详情页，开启最下面的两个开关。'
                : 'The tunnel is up. We recommend turning on system-level protection '
                    '(Always-on VPN + block connections without VPN) so traffic never slips out of '
                    'the tunnel when the app restarts or the link drops.\n\n'
                    'Note: with "Block connections without VPN" on, the phone will have no network '
                    'while the VPN is manually disconnected until it reconnects — that is this '
                    'setting working as designed, not a fault.\n\n'
                    'In the VPN list, find WildLime VPN, open its details and turn on the last two switches.',
            icon: Icons.security_outlined,
            positiveBtnTxt: isZh ? '去设置' : 'Open settings',
          ),
        ) ??
        false;
    await ref.read(Preferences.lockdownGuideShown.notifier).update(true);
    if (goSettings) {
      try {
        await const MethodChannel('com.nublime.app/method').invokeMethod('openVpnSettings');
      } catch (_) {}
    }
  }

  Future<void> showProxyInfo({required OutboundGroupItemInfo outboundInfo}) async {
    return await _show<void>(ProxyInfoDialog(outboundInfo: outboundInfo));
  }

  Future<String?> showSettingText({
    required String lable,
    String value = '',
    String? defaultValue,
    FormFieldValidator<String>? validator,
  }) async {
    return await _show<String?>(
      SettingTextDialog(lable: lable, value: value, defaultValue: defaultValue, validator: validator),
    );
  }

  Future<List<RouteEnumValue>?> showSettingCheckbox({
    required String title,
    required List<RouteEnumValue> values,
    required List<RouteEnumValue> selectedValues,
    List<RouteEnumValue>? defaultValue,
    Map<String, String>? t,
  }) async {
    return await _show<List<RouteEnumValue>?>(
      SettingCheckboxDialog(
        title: title,
        values: values,
        selectedValues: selectedValues,
        defaultValue: defaultValue,
        t: t,
      ),
    );
  }

  Future<T?> showSettingRadio<T>({
    required String title,
    required List<T> values,
    required T value,
    T? defaultValue,
    Map<String, String>? t,
  }) async {
    return await _show<T?>(
      SettingRadioDialog(title: title, values: values, value: value, defaultValue: defaultValue, t: t),
    );
  }

  Future<T?> showSettingInput<T>({
    required String title,
    required T initialValue,
    T? Function(String value)? mapTo,
    bool Function(String value)? validator,
    String Function(T value)? valueFormatter,
    List<T>? possibleValues,
    VoidCallback? onReset,
    (String text, VoidCallback)? optionalAction,
    IconData? icon,
    bool digitsOnly = false,
  }) async {
    return await _show<T?>(
      SettingInputDialog(
        title: title,
        initialValue: initialValue,
        mapTo: mapTo,
        validator: validator,
        valueFormatter: valueFormatter,
        possibleValues: possibleValues,
        onReset: onReset,
        optionalAction: optionalAction,
        icon: icon,
        digitsOnly: digitsOnly,
      ),
    );
  }

  Future<T?> showSettingPicker<T>({
    required String title,
    bool showFlag = false,
    required T selected,
    required List<T> options,
    required String Function(T e) getTitle,
    VoidCallback? onReset,
  }) async {
    return await _show<T?>(
      SettingPickerDialog(
        title: title,
        showFlag: showFlag,
        selected: selected,
        options: options,
        getTitle: getTitle,
        onReset: onReset,
      ),
    );
  }

  Future<bool?> showSave({required String title, required String description}) async {
    return await _show<bool?>(SaveDialog(title: title, description: description));
  }

  Future<void> showWindowClosing() async {
    return await _show<void>(const WindowClosingDialog());
  }

  Future<void> showCustomAlert({String? title, required String message}) async {
    return await _show<void>(CustomAlertDialog(title: title, message: message));
  }

  Future<void> showCustomAlertFromErr(({String type, String? message}) err) async {
    return await _show<void>(CustomAlertDialog.fromErr(err));
  }
}
