// B-3 (deployment spec §5, "动态节点下发"): node delivery is backend-driven and
// rotatable — "节点列表从后端实时拉取、可轮换、被封即换；客户端不硬编码 IP/Reality
// 密钥（反编译也拿不到固定服务器清单）"。
//
// This refresher runs before EVERY connect attempt: it pulls the current single-node
// config from the production activation backend with the stored auth token and rotates
// the delivered profile file THROUGH THE ONE COMMIT PATH (validateConfigByPath) — the
// R27 converter + schema validator + R18.1 atomic-rename semantics therefore apply to
// refreshes too:
//
//   - success  → configs/<profileId>.json is atomically replaced by the converted,
//                schema-valid Xray artifact; the staged input is consumed.
//   - failure  → the previous valid delivered file is PRESERVED byte-for-byte (a
//                broken or hostile backend response can never brick the last
//                known-good node); the staged input is cleaned up best-effort and
//                the connect proceeds with the existing artifact.
//   - offline / no token / non-200 → Left; connect proceeds unchanged. There is
//                deliberately NO built-in fallback node (R02 / B-3).
//
// Rotation cadence: every connect attempt (plus t60's activation-time fetch).
// "被封即换" is backend-driven: when a node is blocked the backend switches the
// default node, and clients pick up the new artifact on the next connect's refresh.

import 'package:fpdart/fpdart.dart';

import 'package:nublime/core/utils/single_call.dart';
import 'package:nublime/features/profile/data/profile_path_resolver.dart';
import 'package:nublime/features/profile/data/profile_repository.dart';
import 'package:nublime/features/profile/model/profile_failure.dart';
import 'package:nublime/nublimecore/nublime_core_service.dart';

/// The endpoint shapes live in node_catalog.dart (one definition, pinned by tests):
/// `single=true` for the backend default node, `server_id=<id>` for a picked node.
export 'node_catalog.dart' show kNodeConfigEndpoint, nodeConfigEndpoint;

/// Raw fetch outcome: HTTP status code and body (body null on transport failure).
/// Hand-fakeable in tests — no HTTP client mocking package needed.
typedef RawConfigFetch = Future<({int status, String? body})> Function();

/// Atomic rotation of the delivered config file for [id] — the B-3 write path in
/// isolation: same-directory staged input → the ONE commit path (R27 convert →
/// validate → R18.1 atomic rename) → best-effort staged cleanup on rejection.
///
/// Kept as a free function (not a repository method body) so it is testable with a
/// real [ProfilePathResolver] and a real [NuBLimeCoreService] and no repository
/// scaffolding. The repository's `rotateDeliveredConfig` is a one-line delegate.
Future<Either<ProfileFailure, Unit>> rotateDeliveredFile({
  required ProfilePathResolver resolver,
  required NuBLimeCoreService service,
  required String id,
  required String content,
}) async {
  final target = resolver.file(id);
  final staged = resolver.tempFile(id);
  try {
    staged.parent.createSync(recursive: true);
    staged.writeAsStringSync(content, flush: true);
  } catch (e) {
    return left(ProfileFailure.unexpected('staging failed: $e'));
  }
  final verdict =
      await service.validateConfigByPath(target.path, staged.path, false).run();
  return verdict.fold(
    (l) {
      // Best-effort cleanup of the rejected input; the service deliberately does
      // not consume a staged input on a failed commit (R18.1 §7.2), and the
      // previous valid delivered file is untouched.
      try {
        if (staged.existsSync()) staged.deleteSync();
      } catch (_) {}
      return left(ProfileFailure.invalidConfig(l));
    },
    (u) => right(u),
  );
}

/// Rotates the backend-delivered node config into the delivered-profile file.
///
/// Pure orchestration on injected dependencies: the fetch closure (auth headers are
/// the caller's concern), the active profile id reader, and the profile repository
/// (whose `rotateDeliveredConfig` performs the atomic commit).
class RemoteConfigRefresher {
  RemoteConfigRefresher({
    required RawConfigFetch fetch,
    required Future<String?> Function() activeProfileId,
    required ProfileRepository repository,
  })  : _fetch = fetch,
        _activeProfileId = activeProfileId,
        _repository = repository;

  final RawConfigFetch _fetch;
  final Future<String?> Function() _activeProfileId;
  final ProfileRepository _repository;

  /// Fetches the current node config and rotates the delivered file.
  ///
  /// A Left NEVER blocks a connect — callers log it and proceed with the existing
  /// artifact (there is no built-in fallback).
  Future<Either<String, Unit>> refreshDeliveredConfig() async {
    final profileId = await _activeProfileId();
    if (profileId == null || profileId.isEmpty) {
      return left('no active profile — nothing to rotate');
    }
    final ({int status, String? body}) res;
    try {
      res = await _fetch();
    } catch (e) {
      return left('node config fetch failed: $e');
    }
    if (res.status != 200 || res.body == null || res.body!.isEmpty) {
      return left('node config fetch rejected: status=${res.status}');
    }
    final outcome =
        await _repository.rotateDeliveredConfig(profileId, res.body!).run();
    return outcome.mapLeft((failure) => 'rotation rejected: $failure');
  }
}

/// Single-flight wrapper for the B-3 refresh (R28-F1/F3, Astra).
///
/// Both connection entry points call [refreshOnce]: the connect path
/// (`_connectThrottled`) and the reconnect path (profile switch / country dropdown).
/// The coordinator owns the gate, so two entries can never interleave writes to the
/// same per-id staged file; a call that lands while a refresh is running is skipped
/// (a refresh was just attempted, the artifact it produced is fresh).
///
/// Never throws: outcomes are reported through the callbacks.
class B3RefreshCoordinator {
  B3RefreshCoordinator({required RemoteConfigRefresher refresher, SingleCall? gate})
      : _refresher = refresher,
        _gate = gate ?? SingleCall();

  final RemoteConfigRefresher _refresher;
  final SingleCall _gate;

  Future<void> refreshOnce({
    void Function(String reason)? onSkipped,
    void Function(String reason)? onFailed,
  }) async {
    await _gate.run(() async {
      try {
        final outcome = await _refresher.refreshDeliveredConfig();
        outcome.fold((l) => onSkipped?.call(l), (_) => null);
      } catch (e) {
        onFailed?.call(e.toString());
      }
    }, onIgnored: null);
  }
}
