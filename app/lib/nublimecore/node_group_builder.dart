// WO-6: single-node group contract for the UI.
//
// The deployment has exactly ONE dial-able node, but the UI's group/node card is built for
// a multi-node world. This builder turns the committed Xray config into the one group the
// UI renders, so B-3 (dynamic node delivery, multi-node) can later replace the CONTENT
// without the UI contract silently breaking — the shape is pinned by
// test/r31c_node_group_test.dart.
//
// Resolution order for the dialed node (mirrors the converter's discipline — never guess a
// different node than the backend selected):
//   1. routing.rules[].outboundTag that names a vless outbound (first match);
//   2. legacy `route.final` naming a vless outbound;
//   3. the single vless outbound (single-node deployment).
// No vless outbound → null group (the UI then shows no node card rather than a fiction).

import 'package:nublime/nublimecore/model/core_types.dart';

class NodeGroupBuilder {
  NodeGroupBuilder._();

  static const String groupTag = 'proxy';
  static const String groupType = 'selector';

  /// Builds the single-node group from an Xray-shaped config map; null when no node.
  static OutboundGroupInfo? fromXrayConfig(Map<String, dynamic> config) {
    final outbounds = config['outbounds'];
    if (outbounds is! List) return null;

    final vlessTags = <String>[];
    for (final dynamic ob in outbounds) {
      if (ob is Map && ob['protocol'] == 'vless' && ob['tag'] is String) {
        vlessTags.add(ob['tag'] as String);
      }
    }
    if (vlessTags.isEmpty) return null;

    String? chosen;
    // 1. routing rules
    final routing = config['routing'];
    if (routing is Map) {
      final rules = routing['rules'];
      if (rules is List) {
        for (final dynamic rule in rules) {
          if (rule is Map) {
            final tag = rule['outboundTag'];
            if (tag is String && vlessTags.contains(tag)) {
              chosen = tag;
              break;
            }
          }
        }
      }
    }
    // 2. legacy route.final
    if (chosen == null) {
      final route = config['route'];
      if (route is Map) {
        final finalTag = route['final'];
        if (finalTag is String && vlessTags.contains(finalTag)) chosen = finalTag;
      }
    }
    // 3. the single vless outbound
    chosen ??= vlessTags.first;

    Map<dynamic, dynamic>? node;
    for (final dynamic ob in outbounds) {
      if (ob is Map && ob['tag'] == chosen) {
        node = ob;
        break;
      }
    }

    var host = '';
    var port = 0;
    final settings = node?['settings'];
    if (settings is Map) {
      final vnext = settings['vnext'];
      if (vnext is List && vnext.isNotEmpty && vnext.first is Map) {
        final first = vnext.first as Map;
        if (first['address'] is String) host = first['address'] as String;
        if (first['port'] is int) port = first['port'] as int;
      }
    }
    // Production Xray configs may instead carry a flat server/server_port pair.
    if (host.isEmpty && node?['server'] is String) host = node!['server'] as String;
    if (port == 0 && node?['server_port'] is int) port = node!['server_port'] as int;

    return OutboundGroupInfo(
      tag: groupTag,
      type: groupType,
      selected: chosen,
      items: [
        OutboundGroupItemInfo(
          tag: chosen,
          type: 'vless',
          host: host,
          port: port,
          isSelected: true,
        ),
      ],
    );
  }
}
