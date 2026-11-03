// B-3 (deployment spec §5, "动态节点下发") — client side of multi-node delivery.
//
// The backend is the single source of truth for which nodes exist and which of them can
// actually render a config (nodes failing the render guard are filtered out server-side, so
// everything in this catalog is connectable). The client therefore:
//
//   - fetches the catalog from /api/app/servers (authenticated, same token as the config);
//   - remembers the user's pick locally (a node id — never a host/port/key, so nothing
//     hard-coded ships in the APK);
//   - asks the config endpoint for THAT node (?server_id=...), or for the backend default
//     when nothing is picked (?single=true).
//
// No fallback node exists on purpose (R02 / B-3): an empty or failed catalog means "keep the
// last known-good delivered artifact", not "connect somewhere else".

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Authenticated node catalog (only renderable nodes are listed by the backend).
const String kServersEndpoint = 'https://www.nublime.com/api/app/servers';

/// The single-node default config endpoint (backend's default/active node).
const String kNodeConfigEndpoint =
    'https://www.nublime.com/api/app/config/singbox?single=true';

/// Config endpoint for a specific node id, or the backend default when [serverId] is null
/// or empty. Kept as one pure function so the URL shape is pinned by tests and both call
/// sites (activation fetch + pre-connect refresh) cannot drift apart.
String nodeConfigEndpoint({String? serverId}) {
  final id = (serverId ?? '').trim();
  if (id.isEmpty) return kNodeConfigEndpoint;
  return 'https://www.nublime.com/api/app/config/singbox?server_id=${Uri.encodeQueryComponent(id)}';
}

/// One catalog entry. `host`/`port` are for DISPLAY only — the connect path never reads
/// them; the rendered config is always produced by the backend.
class NodeInfo {
  const NodeInfo({
    required this.id,
    required this.country,
    required this.host,
    required this.port,
    this.flag = '🌐',
    this.protocol = 'VLESS_REALITY',
    this.load = 0,
    this.isRecommended = false,
  });

  final String id;
  final String country;
  final String host;
  final int port;
  final String flag;
  final String protocol;
  final int load;
  final bool isRecommended;

  bool get isMultihop => load > 0 && load >= 90;

  @override
  String toString() => 'NodeInfo($country, $host:$port, recommended=$isRecommended)';
}

/// Parses the /api/app/servers payload.
///
/// The endpoint returns a bare JSON array. Anything unexpected raises [FormatException] and
/// the caller keeps the previous catalog — a malformed backend response must never empty the
/// picker or silently switch the user's node.
List<NodeInfo> parseServers(String body) {
  final decoded = _decode(body);
  if (decoded is! List) {
    throw const FormatException('servers payload is not a list');
  }
  final nodes = <NodeInfo>[];
  for (final raw in decoded) {
    if (raw is! Map) continue;
    final id = (raw['id'] ?? '').toString().trim();
    if (id.isEmpty) continue; // a node without an id can never be selected
    nodes.add(NodeInfo(
      id: id,
      country: (raw['country'] ?? raw['city'] ?? '').toString(),
      host: (raw['host'] ?? '').toString(),
      port: _asInt(raw['port']),
      flag: (raw['flag'] ?? '🌐').toString(),
      protocol: (raw['protocol'] ?? 'VLESS_REALITY').toString(),
      load: _asInt(raw['load']),
      isRecommended: raw['isRecommended'] == true,
    ));
  }
  return nodes;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException catch (e) {
    throw FormatException('servers payload is not JSON: ${e.message}');
  }
}

/// Local pick persistence. Only the node id is stored — never credentials.
class SelectedNodeStore {
  static const String key = 'b3_selected_server_id';

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(key);
    return (id == null || id.trim().isEmpty) ? null : id.trim();
  }

  Future<void> write(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, serverId.trim());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// Keeps the pick only if the node still exists in [nodes]; otherwise clears it so the
  /// client falls back to the backend default instead of requesting a dead node forever.
  Future<String?> reconcile(List<NodeInfo> nodes) async {
    final id = await read();
    if (id == null) return null;
    final stillThere = nodes.any((n) => n.id == id);
    if (!stillThere) {
      await clear();
      return null;
    }
    return id;
  }
}
