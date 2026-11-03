// B-3: the node catalog the picker is built from.
//
// Backend-side, /api/app/servers already filters out nodes the renderer refuses (so every
// entry is connectable) and returns display data only. This provider never caches across
// sessions: a stale catalog is a stale picker, and "被封即换" depends on the list being
// fresh at the moment the user opens the sheet.
//
// Failure policy: an error or non-200 yields an empty list, and the home page then shows the
// static "auto" label — the picker disappears rather than offering nodes the backend cannot
// render (R02 / B-3: no built-in fallback, no invented nodes).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggy/loggy.dart';

import 'package:nublime/core/auth/auth_token_refresher.dart';

import 'package:nublime/features/profile/data/node_catalog.dart';
import 'package:nublime/utils/custom_loggers.dart';

final Loggy<AppLogger> _log = Loggy<AppLogger>('nodeCatalog');

/// Fetches the authenticated node catalog. Empty list on any failure (never throws into the UI).
final nodeCatalogProvider = FutureProvider.autoDispose<List<NodeInfo>>((ref) async {
  try {
    // AuthorizedClient renews an expired token once and retries — without this the picker
    // silently disappears 30 days after activation (401), which is how B-3 died in the field.
    final res = await AuthorizedClient().get(Uri.parse(kServersEndpoint));
    if (res.status != 200) {
      _log.info('[B-3] catalog rejected: status=${res.status}');
      return const <NodeInfo>[];
    }
    final body = res.body;
    if (body == null || body.isEmpty) return const <NodeInfo>[];
    final nodes = parseServers(body);
    // A pick pointing at a node the backend no longer offers must not survive: it would
    // make every connect request a dead server_id.
    final kept = await SelectedNodeStore().reconcile(nodes);
    _log.info(
          '[B-3] catalog=${nodes.length} nodes, kept pick=$kept',
        );
    return nodes;
  } catch (e) {
    _log.info('[B-3] catalog fetch failed: $e');
    return const <NodeInfo>[];
  }
});

/// True when at least one node (besides the backend default) can be picked.
extension NodeCatalogPickable on List<NodeInfo> {
  bool get hasChoice => length > 1;
}
