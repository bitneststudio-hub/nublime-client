import 'package:nublime/nublimecore/model/core_types.dart';
import 'package:flutter/material.dart';
import 'package:nublime/core/router/dialog/dialog_notifier.dart';
import 'package:nublime/features/proxy/active/ip_widget.dart';
import 'package:nublime/gen/fonts.gen.dart';
import 'package:nublime/utils/custom_loggers.dart';
import 'package:nublime/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxyTile extends HookConsumerWidget with PresLogger {
  const ProxyTile(this.proxy, {super.key, required this.selected, required this.onTap});

  final OutboundGroupItemInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListTile(
      // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        proxy.tagDisplay,
        overflow: TextOverflow.ellipsis,
        style: PlatformUtils.isWindows ? null : null,
      ),
      leading: IPCountryFlag(
        countryCode: proxy.ipinfo?.countryCode ?? '',
        organization: proxy.ipinfo?.org,
        size: 40,
        padding: const EdgeInsetsDirectional.only(end: 8),
      ),
      subtitle: Text.rich(
        TextSpan(
          text: proxy.type,
          children: [
            if (proxy.isGroup)
              TextSpan(
                text: ' (${proxy.groupSelectedTagDisplay.trim()})',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        children: [
          if (proxy.urlTestDelay != 0)
            Text(
              proxy.urlTestDelay > 65000 ? "×" : proxy.urlTestDelay.toString(),
              style: TextStyle(color: delayColor(context, proxy.urlTestDelay)),
            ),

          if (proxy.download > 0) Text("⬩", style: Theme.of(context).textTheme.bodySmall),
        ],
      ),

      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer,
      onTap: onTap,
      onLongPress: () async => await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: proxy),
      horizontalTitleGap: 4,
    );
  }

  Color delayColor(BuildContext context, int delay) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return switch (delay) {
        < 800 => Colors.lightGreen,
        < 1500 => Colors.orange,
        _ => Colors.redAccent,
      };
    }
    return switch (delay) {
      < 800 => Colors.green,
      < 1500 => Colors.deepOrangeAccent,
      _ => Colors.red,
    };
  }
}
