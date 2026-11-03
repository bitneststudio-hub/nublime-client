// lib/features/home/t58_server_selector.dart
import 'package:flutter/material.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/features/connection/notifier/connection_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ServerOption {
  final String flag;
  final String name;
  final String code;
  final bool isDefault;
  final bool comingSoon;

  const ServerOption({
    required this.flag,
    required this.name,
    required this.code,
    this.isDefault = false,
    this.comingSoon = false,
  });

  static const List<ServerOption> all = [
    ServerOption(flag: '🇩🇪', name: '德国', code: 'DE', isDefault: true),
    ServerOption(flag: '🇦🇺', name: '澳大利亚', code: 'AU'),
    ServerOption(flag: '🇳🇿', name: '新西兰', code: 'NZ'),
    ServerOption(flag: '🇯🇵', name: '日本', code: 'JP', comingSoon: true),
  ];
}

class T58ServerSelector extends HookConsumerWidget {
  const T58ServerSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final isConnected = connectionStatus.valueOrNull?.isConnected ?? false;
    return _SelectorBody(isConnected: isConnected);
  }
}

class _SelectorBody extends StatefulWidget {
  final bool isConnected;
  const _SelectorBody({required this.isConnected});
  @override
  State<_SelectorBody> createState() => _SelectorBodyState();
}

class _SelectorBodyState extends State<_SelectorBody> {
  ServerOption _selected = ServerOption.all.first;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuBLimeColors.border0),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Text(_selected.flag, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_selected.name,
                            style: const TextStyle(
                                color: NuBLimeColors.text0,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        Text(
                          _selected.isDefault && !widget.isConnected
                              ? '⭐ 默认推荐'
                              : widget.isConnected
                                  ? '● 已连接'
                                  : '○ 未连接',
                          style: TextStyle(
                            color: _selected.isDefault && !widget.isConnected
                                ? NuBLimeColors.lemon
                                : widget.isConnected
                                    ? NuBLimeColors.connected
                                    : NuBLimeColors.text3,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: NuBLimeColors.text2,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ...ServerOption.all.map((server) {
              final isSelected = server.code == _selected.code;
              return InkWell(
                onTap: server.comingSoon
                    ? null
                    : () => setState(() {
                          _selected = server;
                          _expanded = false;
                        }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? NuBLimeColors.bg3 : Colors.transparent,
                    border: const Border(top: BorderSide(color: NuBLimeColors.border0)),
                  ),
                  child: Row(
                    children: [
                      Text(server.flag, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          server.name,
                          style: TextStyle(
                            color: server.comingSoon
                                ? NuBLimeColors.text3
                                : isSelected
                                    ? NuBLimeColors.lemon
                                    : NuBLimeColors.text0,
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (server.comingSoon)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: NuBLimeColors.bg3,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: NuBLimeColors.border1),
                          ),
                          child: const Text('即将开通',
                              style: TextStyle(color: NuBLimeColors.text3, fontSize: 11)),
                        )
                      else if (isSelected)
                        const Icon(Icons.check_circle, color: NuBLimeColors.lemon, size: 18),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
