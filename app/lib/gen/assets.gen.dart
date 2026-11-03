/// GENERATED CODE - DO NOT MODIFY BY HAND
/// *****************************************************
///  FlutterGen
/// *****************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: directives_ordering,unnecessary_import,implicit_dynamic_list_literal,deprecated_member_use

import 'package:flutter/widgets.dart';

class $AssetsIconGen {
  const $AssetsIconGen();

  /// File path: assets/icon/icon_144x144.png
  AssetGenImage get icon144x144 =>
      const AssetGenImage('assets/icon/icon_144x144.png');

  /// File path: assets/icon/icon_192x192.png
  AssetGenImage get icon192x192 =>
      const AssetGenImage('assets/icon/icon_192x192.png');

  /// File path: assets/icon/icon_48x48.png
  AssetGenImage get icon48x48 =>
      const AssetGenImage('assets/icon/icon_48x48.png');

  /// File path: assets/icon/icon_512x512.png
  AssetGenImage get icon512x512 =>
      const AssetGenImage('assets/icon/icon_512x512.png');

  /// File path: assets/icon/icon_72x72.png
  AssetGenImage get icon72x72 =>
      const AssetGenImage('assets/icon/icon_72x72.png');

  /// File path: assets/icon/icon_96x96.png
  AssetGenImage get icon96x96 =>
      const AssetGenImage('assets/icon/icon_96x96.png');

  /// File path: assets/icon/nublime_512x512.png
  AssetGenImage get nublime512x512 =>
      const AssetGenImage('assets/icon/nublime_512x512.png');

  /// File path: assets/icon/nublime_red_128x128.png
  AssetGenImage get nublimeRed128x128 =>
      const AssetGenImage('assets/icon/nublime_red_128x128.png');

  /// File path: assets/icon/nublime_red_16x16.png
  AssetGenImage get nublimeRed16x16 =>
      const AssetGenImage('assets/icon/nublime_red_16x16.png');

  /// File path: assets/icon/nublime_red_256x256.png
  AssetGenImage get nublimeRed256x256 =>
      const AssetGenImage('assets/icon/nublime_red_256x256.png');

  /// File path: assets/icon/nublime_red_32x32.png
  AssetGenImage get nublimeRed32x32 =>
      const AssetGenImage('assets/icon/nublime_red_32x32.png');

  /// File path: assets/icon/nublime_red_48x48.png
  AssetGenImage get nublimeRed48x48 =>
      const AssetGenImage('assets/icon/nublime_red_48x48.png');

  /// File path: assets/icon/nublime_red_512x512.png
  AssetGenImage get nublimeRed512x512 =>
      const AssetGenImage('assets/icon/nublime_red_512x512.png');

  /// File path: assets/icon/nublime_red_64x64.png
  AssetGenImage get nublimeRed64x64 =>
      const AssetGenImage('assets/icon/nublime_red_64x64.png');

  /// List of all assets
  List<AssetGenImage> get values => [
    icon144x144,
    icon192x192,
    icon48x48,
    icon512x512,
    icon72x72,
    icon96x96,
    nublime512x512,
    nublimeRed128x128,
    nublimeRed16x16,
    nublimeRed256x256,
    nublimeRed32x32,
    nublimeRed48x48,
    nublimeRed512x512,
    nublimeRed64x64,
  ];
}

class $AssetsImagesGen {
  const $AssetsImagesGen();

  /// File path: assets/images/connect_norouz.PNG
  AssetGenImage get connectNorouz =>
      const AssetGenImage('assets/images/connect_norouz.PNG');

  /// File path: assets/images/disconnect_norouz.PNG
  AssetGenImage get disconnectNorouz =>
      const AssetGenImage('assets/images/disconnect_norouz.PNG');

  /// Directory path: assets/images/source
  $AssetsImagesSourceGen get source => const $AssetsImagesSourceGen();

  /// File path: assets/images/tray_icon.ico
  String get trayIconIco => 'assets/images/tray_icon.ico';

  /// File path: assets/images/tray_icon.png
  AssetGenImage get trayIconPng =>
      const AssetGenImage('assets/images/tray_icon.png');

  /// File path: assets/images/tray_icon_connected.ico
  String get trayIconConnectedIco => 'assets/images/tray_icon_connected.ico';

  /// File path: assets/images/tray_icon_connected.png
  AssetGenImage get trayIconConnectedPng =>
      const AssetGenImage('assets/images/tray_icon_connected.png');

  /// File path: assets/images/tray_icon_dark.ico
  String get trayIconDarkIco => 'assets/images/tray_icon_dark.ico';

  /// File path: assets/images/tray_icon_dark.png
  AssetGenImage get trayIconDarkPng =>
      const AssetGenImage('assets/images/tray_icon_dark.png');

  /// File path: assets/images/tray_icon_disconnected.ico
  String get trayIconDisconnectedIco =>
      'assets/images/tray_icon_disconnected.ico';

  /// File path: assets/images/tray_icon_disconnected.png
  AssetGenImage get trayIconDisconnectedPng =>
      const AssetGenImage('assets/images/tray_icon_disconnected.png');

  /// File path: assets/images/world_map.png
  AssetGenImage get worldMap =>
      const AssetGenImage('assets/images/world_map.png');

  /// List of all assets
  List<dynamic> get values => [
    connectNorouz,
    disconnectNorouz,
    trayIconIco,
    trayIconPng,
    trayIconConnectedIco,
    trayIconConnectedPng,
    trayIconDarkIco,
    trayIconDarkPng,
    trayIconDisconnectedIco,
    trayIconDisconnectedPng,
    worldMap,
  ];
}

class $AssetsImagesSourceGen {
  const $AssetsImagesSourceGen();

  /// File path: assets/images/source/ic_launcher_border.png
  AssetGenImage get icLauncherBorder =>
      const AssetGenImage('assets/images/source/ic_launcher_border.png');

  /// List of all assets
  List<AssetGenImage> get values => [icLauncherBorder];
}

class Assets {
  const Assets._();

  static const $AssetsIconGen icon = $AssetsIconGen();
  static const $AssetsImagesGen images = $AssetsImagesGen();
}

class AssetGenImage {
  const AssetGenImage(this._assetName, {this.size, this.flavors = const {}});

  final String _assetName;

  final Size? size;
  final Set<String> flavors;

  Image image({
    Key? key,
    AssetBundle? bundle,
    ImageFrameBuilder? frameBuilder,
    ImageErrorWidgetBuilder? errorBuilder,
    String? semanticLabel,
    bool excludeFromSemantics = false,
    double? scale,
    double? width,
    double? height,
    Color? color,
    Animation<double>? opacity,
    BlendMode? colorBlendMode,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    ImageRepeat repeat = ImageRepeat.noRepeat,
    Rect? centerSlice,
    bool matchTextDirection = false,
    bool gaplessPlayback = true,
    bool isAntiAlias = false,
    String? package,
    FilterQuality filterQuality = FilterQuality.medium,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return Image.asset(
      _assetName,
      key: key,
      bundle: bundle,
      frameBuilder: frameBuilder,
      errorBuilder: errorBuilder,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      scale: scale,
      width: width,
      height: height,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      gaplessPlayback: gaplessPlayback,
      isAntiAlias: isAntiAlias,
      package: package,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }

  ImageProvider provider({AssetBundle? bundle, String? package}) {
    return AssetImage(_assetName, bundle: bundle, package: package);
  }

  String get path => _assetName;

  String get keyName => _assetName;
}
