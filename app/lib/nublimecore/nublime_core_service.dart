/// Core VPN service for the Xray-based core.
///
/// Replaces the legacy gRPC `NuBLimeCoreService` (gRPC → hcore). This
/// version bridges to the Android `XrayVpnService` via MethodChannel (commands)
/// and EventChannel (status stream). No gRPC, no protobuf, no legacy core.
///
/// P1 scope (minimal viable): connect / disconnect / status are REAL.
/// Node selection, stats, logs are STUBBED (see the TODO markers) — their
/// types are defined in `model/core_types.dart` and the method signatures are
/// kept stable so a later P1 step can fill them in without a second migration.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';

import 'package:nublime/utils/custom_loggers.dart';
import 'package:nublime/features/connection/model/connection_failure.dart';
import 'package:nublime/nublimecore/model/core_status.dart';
import 'package:nublime/nublimecore/model/core_types.dart';
import 'package:nublime/nublimecore/model/stats_rate_calculator.dart';
import 'package:nublime/nublimecore/node_group_builder.dart';
import 'package:nublime/nublimecore/singbox_xray_converter.dart';

/// Reality uTLS fingerprint（本地可切换开关；远程下发属 P1-next 动态节点范围）。
/// 当前生产值 randomized：2026-09-10 真机 A/B 实测 randomized 与 chrome 各 10/10 握手成功
/// （存档：~/Downloads/WildLime_fingerprint_randomized_验证存档_20260910.md）。
/// 若线上反馈 Reality 握手异常，把这一行改回 'chrome' 即可，无需改动其他逻辑。
/// 2026-09-28 真机根因定位：`randomized` 指纹在 libXray(utls v1.8.3-20260301 / Go 1.26.3)
/// 下握手失败（GoLog: `tls: CurvePreferences includes unsupported curve`），数据面全超时；
/// 同会话 `chrome` 指纹数据面正常（curl 出口=节点 IP ×3, rc=0）。
/// 依据：05_审核请求/fingerprint_rootcause_20260928.md（A/B 实验原始记录）
const String kRealityFingerprint = 'chrome';

class NuBLimeCoreService with InfraLogger {
  static const MethodChannel _channel = MethodChannel('com.nublime.vpn/vpn');
  static const EventChannel _statusChannel = EventChannel('com.nublime.vpn/status');
  /// WO-5: cumulative traffic counters, pushed once per second by the service.
  static const EventChannel _statsChannel = EventChannel('com.nublime.vpn/stats');

  /// WO-6: the last SUCCESSFULLY committed Xray config, used to emit the single-node
  /// group for the UI. Best-effort (the group card must never affect the config contract).
  Map<String, dynamic>? _lastCommittedConfig;

  Future<void> init() async {
    // Nothing to init for the MethodChannel bridge. Kept for API parity.
  }

  /// R02 (Astra 10-09 §4.2): Xray-schema discrimination. `outbounds is List` alone cannot
  /// tell an Xray config from a legacy box-style config (both have an outbounds list) and
  /// accepts an empty/scalar list, which is not a usable VPN config. The validator now checks
  /// Xray-SPECIFIC outbound shapes: each outbound must be an object carrying `protocol`
  /// (Xray uses "protocol"; legacy box configs use "type"), and the list must be non-empty.
  /// An empty outbounds list or any non-object/scalar entry is rejected.
  @visibleForTesting
  static Either<String, Map<String, dynamic>> validateXrayConfigContent(String content) {
    if (content.trim().isEmpty) return left('profile content is empty');
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (e) {
      return left('profile content is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      return left('profile content is not a JSON object (Xray config required)');
    }
    final outbounds = decoded['outbounds'];
    if (outbounds is! List || outbounds.isEmpty) {
      return left('profile has no outbounds (not an Xray-usable config)');
    }
    // Astra 10-09 §4.2 (SCHEMA): every outbound must be an Xray outbound object — a Map
    // with a `protocol` field. Legacy box-style outbounds carry `type`/`server` instead;
    // empty lists and scalar entries were previously admitted and are now rejected.
    for (final ob in outbounds) {
      if (ob is! Map || ob['protocol'] is! String || (ob['protocol'] as String).isEmpty) {
        return left('profile outbounds are not Xray-shaped (missing "protocol"); '
            'unsupported config format rejected');
      }
    }
    return right(decoded);
  }

  TaskEither<String, Unit> validateConfigByPath(String path, String tempPath, bool debug) {
    return TaskEither(() async {
      // Read the staged content first; nothing is committed until it validates.
      // Astra 10-09 §4.3: ALL I/O failures become Left — a commit failure must never
      // throw past the TaskEither contract and must never lose the previous valid profile.
      try {
        final tempFile = File(tempPath);
        if (!tempFile.existsSync()) {
          return left('staged profile not found: $tempPath');
        }
        final rawContent = tempFile.readAsStringSync();
        // R2-6: ONE converter, same discipline as the ONE validator (R02, Astra 10-09
        // §4.2). A legacy sing-box delivery — a fresh fetch from the activation
        // backend, or a pre-rebuild file surviving an in-place upgrade — converts
        // IN MEMORY; the commit below persists the CONVERTED artifact only, never a
        // payload the Xray core cannot consume. Xray-shaped content passes through
        // unchanged (the commit then commits exactly what validated, as before).
        final effective = SingboxXrayConverter.effectiveXrayContent(
            rawContent, fingerprint: kRealityFingerprint);
        final conversionErr = effective.fold((l) => l, (_) => null);
        if (conversionErr != null) {
          return left(conversionErr);
        }
        final content = effective.getOrElse((_) => '');
        final validated = validateXrayConfigContent(content);
        return await validated.fold(
          (err) async => left(err),
          (_) async {
            // Astra 10-09 §4.3 (COMMIT_FAILURE): do NOT delete the target first. Write
            // the validated content to a temp file IN THE SAME DIRECTORY as the target,
            // then rename over it — rename is the atomic replacement on one filesystem
            // and leaves the previous valid file intact when it fails. A cross-device
            // rename throws FileSystemException, which is caught below and returned as
            // Left with the old file untouched. On success the STAGED file is consumed
            // (deleted) so no half-processed input remains next to the committed profile.
            final target = File(path);
            final staging = File('${target.path}.commit.tmp');
            // Astra R18.1 §7.2 (COMMIT_CLEANUP): "published" and "input cleanup failed" are
            // SEPARATE outcomes. The previous code classed a post-commit tempFile deletion
            // failure as "commit failed (previous profile preserved)" — reporting failure
            // while the new content was already committed, and promising a preservation
            // that had not happened. Now: commit success returns RIGHT; the staged input's
            // deletion is best-effort/idempotent and NEVER turns an already-published commit
            // into a Left. (The old file itself is only replaced by the atomic rename above.)
            try {
              staging.writeAsStringSync(content, flush: true);
            } on FileSystemException catch (e) {
              return left('profile commit failed: ${e.message} (previous profile preserved)');
            }
            try {
              await staging.rename(target.path);
            } on FileSystemException catch (e) {
              return left('profile commit failed: ${e.message} (previous profile preserved)');
            }
            // Commit is PUBLISHED from here on. Cleanup of the staged INPUT is best-effort:
            // a failure to delete it must not masquerade as a commit failure.
            try {
              if (tempFile.existsSync()) tempFile.deleteSync();
            } on FileSystemException catch (e) {
              // Already committed — report success; the leftover input is harmless debris.
              // Log-worthy but contract-honest: the caller's profile IS the new content.
              // ignore: avoid_print
              print('[validateConfigByPath] staged input cleanup failed (commit already published): ${e.message}');
            }
            // WO-6: remember the committed config for the single-node group card.
            try {
              final committed = jsonDecode(content);
              if (committed is Map<String, dynamic>) _lastCommittedConfig = committed;
            } on FormatException {
              // Not fatal for the UI contract: the group card simply stays absent.
            }
            return right(unit);
          },
        );
      } on FileSystemException catch (e) {
        return left('profile commit I/O error: ${e.message}');
      }
    });
  }

  TaskEither<String, String> generateFullConfigByPath(String path) {
    // R02 (Astra §4.1): return the VALIDATED config CONTENT, not the path string —
    // the previous stub returned the path itself, which callers treated as a config.
    // Astra R18.1 §7.3 (GENERATE_UNREADABLE): ALL read/decode failures become Left —
    // the previous version let file read / JSON decode exceptions escape the
    // TaskEither contract. Same error mapping as start's reader and validateConfigByPath.
    return TaskEither<String, String>(() async {
      try {
        final f = File(path);
        if (!f.existsSync()) return left('profile not found: $path');
        final rawContent = f.readAsStringSync();
        // R2-6: ONE converter (see _readDeliveredConfig). Legacy sing-box content
        // converts in memory; the returned "full config" is always Xray-shaped, the
        // stored file is never rewritten by this preview path.
        return SingboxXrayConverter.effectiveXrayContent(
                rawContent, fingerprint: kRealityFingerprint)
            .flatMap((content) => validateXrayConfigContent(content).map((_) => content));
      } on FileSystemException catch (e) {
        return left('profile unreadable: ${e.message}');
      } on FormatException catch (e) {
        return left('profile is not valid JSON: ${e.message}');
      }
    });
  }

  TaskEither<String, Unit> setup() => TaskEither.of(unit);

  TaskEither<String, Unit> changeOptions(Object options) {
    // TODO(P1-next): apply runtime config options.
    return TaskEither.of(unit);
  }

  /// R02 (Astra): the ONE config reader both start and restart consume. The delivered
  /// profile file (`configs/<id>.json`) is read, validated, and its CONTENT — not a path
  /// string, not any built-in fallback — is what the platform channel receives.
  ///
  /// Missing / empty / unparseable / non-config content fails explicitly: there is
  /// deliberately NO fallback to any built-in node (Astra: REAL_START usesBuiltin=true
  /// was the R02 defect).
  ///
  /// Contract for the delivered file: an Xray-usable config JSON — a JSON object with an
  /// `outbounds` list. The Android side injects the authenticated SOCKS inbound into
  /// `inbounds` and parses the content with JSONObject, so a path or a raw subscription
  /// (URI lines / base64) must never reach the channel.
  TaskEither<ConnectionFailure, String> _readDeliveredConfig(String profilePath) {
    return TaskEither(() async {
      try {
        final f = File(profilePath);
        if (!f.existsSync()) {
          return left(ConnectionFailure.invalidConfig('delivered profile not found: $profilePath'));
        }
        final rawContent = f.readAsStringSync();
        if (rawContent.trim().isEmpty) {
          return left(ConnectionFailure.invalidConfig('delivered profile is empty: $profilePath'));
        }
        final Object? decoded;
        try {
          decoded = jsonDecode(rawContent);
        } on FormatException catch (e) {
          return left(ConnectionFailure.invalidConfig('delivered profile is not valid JSON: ${e.message}'));
        }
        if (decoded is! Map) {
          return left(ConnectionFailure.invalidConfig('delivered profile is not a config JSON object'));
        }
        // Astra 10-09 §4.2 (SCHEMA): ONE validator, used by both the read path and the
        // commit path — the inlined copy previously checked only `outbounds is List` and
        // admitted legacy-box/empty/scalar lists. Delegate to the shared discriminator.
        //
        // R2-6: ONE converter, same discipline. Legacy sing-box content — a pre-rebuild
        // profile file carried over by an in-place app upgrade, or a fresh fetch from
        // the activation backend — converts to the Xray wire shape IN MEMORY here.
        // This read path never rewrites the stored file; the CONVERTED content is
        // what the platform channel receives. Xray-shaped content passes through
        // unchanged, and a converted document is not sing-box-shaped, so re-reading
        // is a no-op (idempotent migration).
        final effective = SingboxXrayConverter.effectiveXrayContent(
            rawContent, fingerprint: kRealityFingerprint);
        if (effective.isLeft()) {
          return left(ConnectionFailure.invalidConfig(
              effective.fold((l) => l, (_) => 'profile rejected by legacy-format migration')));
        }
        final content = effective.getOrElse((_) => '');
        final validated = validateXrayConfigContent(content);
        if (validated.isLeft()) {
          return left(ConnectionFailure.invalidConfig(
              validated.fold((l) => l, (_) => 'profile rejected by schema validation')));
        }
        return right(content);
      } catch (e) {
        return left(ConnectionFailure.unexpected('delivered profile unreadable: $e'));
      }
    });
  }

  /// R02 NEGATIVE-CONTROL REFERENCE (Astra): the built-in single-node config that start/restart
  /// used to send regardless of the delivered profile (REAL_START usesBuiltin=true). Production
  /// code no longer sends it — both commands consume `_readDeliveredConfig(profilePath)`. Kept
  /// ONLY so the regression test's negative control can assert the channel never receives it:
  /// restoring this fallback anywhere in the delivery chain must make the test fail.
  ///
  /// B-3 (deployment spec §5, "动态节点下发"): the template carries DELIBERATELY NON-PRODUCTION
  /// dummy values (RFC 2606 `.invalid` = non-dialable by construction). The shipped kernel must
  /// contain ZERO live node data — decompiling the app must not yield a fixed server list. Real
  /// node data reaches the device only through the backend-delivered profile (t60 fetch /
  /// RemoteConfigRefresher), converted by the ONE converter (R27).
  @visibleForTesting
  static String get r02NegativeControlBuiltin => _defaultXrayConfig;

  static const _defaultXrayConfig = '''{
  "log":{"loglevel":"debug"},
  "inbounds":[],
  "outbounds":[{
    "tag":"proxy",
    "protocol":"vless","settings":{"vnext":[{
      "address":"builtin-negative-control.invalid","port":65535,
      "users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none","flow":"xtls-rprx-vision"}]
    }]},
    "streamSettings":{"network":"tcp","security":"reality","realitySettings":{
      "serverName":"builtin-negative-control.invalid",
      "publicKey":"negative-control-public-key-000000000000",
      "shortId":"00000000","fingerprint":"$kRealityFingerprint"
    }}
  }],
  "routing":{"domainStrategy":"AsIs","rules":[{"type":"field","inboundTag":["socks-in"],"network":"tcp,udp","outboundTag":"proxy"}]}
}''';

  /// §4.3: authoritative session id, set from the acceptance receipt. Events carrying a
  /// different session id are refused; an un-anchored id can never take over the stream.
  String? _anchoredSessionId;
  String? get anchoredSessionId => _anchoredSessionId;

  /// R01 §7: monotonically increasing command generation.
  ///
  /// Every issued command (start / restart / stop) takes the NEXT generation. The generation is
  /// captured when the command is issued and re-checked when its receipt or its post-receipt
  /// snapshot finally arrives: a receipt whose generation is no longer current belongs to a command
  /// that has since been superseded, so it must NOT be allowed to re-anchor the session or publish
  /// state. This closes the late-receipt window (Astra: LATE_RECEIPT / STOP_THEN_LATE_RECEIPT).
  int _commandGeneration = 0;

  /// R02 §4.2 (Astra): generation snapshot BEFORE the async read. The file read is a new
  /// async boundary; if a newer command (stop / start / restart) was issued while the read
  /// was in flight, this command must NOT deliver its startVpn afterwards — the generation
  /// is re-checked immediately before the platform side effect, not only at the receipt.
  TaskEither<ConnectionFailure, Unit> start(
    String profilePath,
    String name,
    bool disableMemoryLimit, {
    String perAppMode = 'off',
    List<String> perAppPackages = const [],
  }) {
    final generationAtIssue = ++_commandGeneration;
    return _readDeliveredConfig(profilePath).flatMap((config) => TaskEither(() async {
      // §4.2: a stop/supersede that landed DURING the read invalidates this command.
      if (generationAtIssue != _commandGeneration) {
        return left(ConnectionFailure.unexpected(
            'start superseded while reading the delivered config (generation $generationAtIssue)'));
      }
      try {
        final generation = generationAtIssue;   // §7: unchanged by the read boundary
        // R01 §4.1: the bridge must answer with the acceptance object. Any other shape is REJECTED —
        // no generic String fallback (a stray "false"/"ERROR: …"/number must never count as accepted).
        final raw = await _channel.invokeMethod<dynamic>('startVpn', {
          'config': config,
          // R36-A05: 分应用名单以前留在 Dart 偏好里没人消费，Kotlin 侧一律全量代理。
          'perAppMode': perAppMode,
          'perAppPackages': perAppPackages,
        });
        if (raw is! Map) {
          return left(ConnectionFailure.unexpected(
              'startVpn returned unexpected type: ${raw.runtimeType}'));
        }
        final accepted = raw['accepted'] == true;
        if (raw['permissionRequired'] == true) {
          return left(ConnectionFailure.missingVpnPermission(
              'VPN permission required (session ${raw['sessionId'] ?? '?'})'));
        }
        if (accepted) {
          // §6: an acceptance WITHOUT a valid session id cannot be treated as accepted.
          final sid = raw['sessionId'];
          if (sid is! String || sid.isEmpty) {
            return left(ConnectionFailure.unexpected(
                'startVpn accepted without a valid sessionId'));
          }
          // §7: a receipt from a superseded command may not re-anchor the session, and must not
          // trigger a snapshot fetch on its behalf either.
          if (generation != _commandGeneration) {
            print('[start] receipt discarded: generation $generation superseded by $_commandGeneration');
            return right(unit);
          }
          _anchoredSessionId = sid;
          // §5: recover the authoritative state — events may have been dropped before this receipt.
          await refreshSnapshot();
          return right(unit);
        }
        return left(ConnectionFailure.unexpected('startVpn not accepted'));
      } catch (e) {
        return left(ConnectionFailure.unexpected(e));
      }
    }));
  }

  /// Astra R24 (STALE_STOP_SID device scenario): an OPTIONAL target session id.
  ///
  /// Production callers pass nothing — the platform side falls back to the live session,
  /// so the shipped behaviour is byte-identical to the previous signature. The parameter
  /// exists ONLY so the fault-injection build can address an ALREADY-SUPERSEDED session
  /// from inside the app (R22 §5: an external adb stop intent is refused by Android's
  /// exported-permission check, so the stale-sid branch could otherwise never be driven).
  ///
  /// Passing a stale sid must NOT stop the live generation: the platform validates the
  /// sid against the live attempt inside the coordination critical section and returns
  /// START_NOT_STICKY without touching it (XrayVpnService.kt onStartCommand L315-331).
  TaskEither<String, Unit> stop([String? targetSessionId]) {
    return TaskEither(() async {
      try {
        _commandGeneration++;   // §7: a stop invalidates every in-flight start/restart receipt
        if (targetSessionId == null || targetSessionId.isEmpty) {
          await _channel.invokeMethod<String>('stopVpn');
        } else {
          await _channel.invokeMethod<String>('stopVpn', {'sessionId': targetSessionId});
        }
        return right(unit);
      } catch (e) {
        return left(e.toString());
      }
    });
  }

  TaskEither<String, Unit> restart(
    String profilePath,
    String name,
    bool disableMemoryLimit, {
    String perAppMode = 'off',
    List<String> perAppPackages = const [],
  }) {
    final generationAtIssue = ++_commandGeneration;
    return TaskEither(() async {
      // R02 (Astra): a restart consumes the SAME delivered-config source as start. Read and
      // validate BEFORE issuing stop — a missing/corrupt profile fails fast without tearing
      // the running session down, and the channel receives the file CONTENT (never the path,
      // never a built-in fallback).
      final read = await _readDeliveredConfig(profilePath).run();
      final String? config = read.fold((_) => null, (content) => content);
      if (config == null) {
        return left('restart: ${read.fold((l) => l.toString(), (_) => '')}');
      }
      // R02 §4.2 (Astra): a stop/supersede that landed DURING the read invalidates this
      // command — the restart must not deliver its stopVpn/startVpn pair afterwards.
      if (generationAtIssue != _commandGeneration) {
        return left('restart superseded while reading the delivered config (generation $generationAtIssue)');
      }
      try {
        final generation = generationAtIssue;   // §7: unchanged by the read boundary
        await _channel.invokeMethod<dynamic>('stopVpn');
        // Astra 10-09 §4.4 (RESTART_STOP): re-check the generation AFTER the stopVpn await
        // and BEFORE issuing any startVpn. A newer stop that completed while this restart was
        // parked on the stop receipt invalidates this command — the late "receipt discarded"
        // print cannot un-send a startVpn that was already delivered. The start side effect
        // is gated here, at the boundary.
        if (generation != _commandGeneration) {
          print('[restart] start suppressed: generation $generation superseded by $_commandGeneration after stop');
          return left('restart superseded while stopping (generation $generation)');
        }
        // R01 §4.1: same acceptance contract as start() — both call sites must agree, no fallback.
        final raw = await _channel.invokeMethod<dynamic>('startVpn', {
          'config': config,
          'perAppMode': perAppMode,
          'perAppPackages': perAppPackages,
        });
        if (raw is! Map) {
          return left('restart: startVpn returned unexpected type: ${raw.runtimeType}');
        }
        if (raw['permissionRequired'] == true) {
          return left('VPN permission required');
        }
        if (raw['accepted'] == true) {
          final sid = raw['sessionId'];
          if (sid is! String || sid.isEmpty) {
            return left('restart accepted without a valid sessionId');
          }
          if (generation != _commandGeneration) {
            print('[restart] receipt discarded: generation $generation superseded by $_commandGeneration');
            return right(unit);
          }
          _anchoredSessionId = sid;
          await refreshSnapshot();
          return right(unit);
        }
        return left('restart not accepted');
      } catch (e) {
        return left(e.toString());
      }
    });
  }

  TaskEither<String, Unit> resetTunnel() {
    // TODO(P1-next): reset the tunnel without a full disconnect.
    return TaskEither.of(unit);
  }

  /// Broadcast output that merges the live EventChannel stream with authoritative snapshots.
  StreamController<CoreEvent>? _statusOut;

  /// Live connection status, pushed from the Android side over an EventChannel.
  ///
  /// §5.1: a (re)subscribing consumer is brought up to date from the authoritative snapshot —
  /// `onListen` fires whenever the listener count goes 0 → 1, so a cancel→listen cycle recovers state.
  Stream<CoreEvent> watchStatus() {
    if (_statusOut != null) return _statusOut!.stream;
    late final StreamController<CoreEvent> out;
    out = StreamController<CoreEvent>.broadcast(
      onListen: () {
        // Same validated path as a receipt-triggered refresh.
        refreshSnapshot();
      },
    );
    _statusOut = out;
    _statusChannel.receiveBroadcastStream().listen(
      _handleRaw,
      onError: (Object e) => print('[watchStatus] stream error: $e'),
    );
    return out.stream;
  }

  /// Pull the authoritative current snapshot (after a start/restart receipt, or on (re)subscribe).
  ///
  /// [generation] pins the request to the command that asked for it. A snapshot whose generation was
  /// superseded while in flight is discarded instead of being allowed to re-anchor the session (§7).
  Future<void> refreshSnapshot([int? generation]) async {
    final gen = generation ?? _commandGeneration;
    try {
      final raw = await _channel.invokeMethod<dynamic>('statusSnapshot');
      if (gen != _commandGeneration) {
        print('[watchStatus] snapshot discarded: generation $gen superseded by $_commandGeneration');
        return;
      }
      if (raw is Map) {
        print('[watchStatus] snapshot pulled: ${raw['status']} session=${raw['sessionId']}');
        _handleRaw(raw, generation: gen);
      }
    } catch (e) {
      print('[statusSnapshot] error: $e');
    }
  }

  /// Single filtering point for snapshots and live events.
  ///
  /// §4/§5.2: identity and sequence are validated BEFORE any internal state changes or publication:
  ///  - a snapshot may establish an anchor only when none is set, and may never overwrite an
  ///    already-anchored session with a different one (anchor never regresses);
  ///  - live events must carry a positive integer seq; only the identity-less initial `Stopped`
  ///    is accepted without one.
  void _handleRaw(dynamic event, {int? generation}) {
    final out = _statusOut;
    if (out == null || out.isClosed) return;
    // §7: an event/snapshot belonging to a superseded command may not change any state.
    if (generation != null && generation != _commandGeneration) {
      print('[watchStatus] drop event of superseded generation $generation (current $_commandGeneration)');
      return;
    }
    if (event is! Map) {
      // Malformed payload: fail safe (never Connected), no session identity.
      out.add(const CoreEvent(status: CoreStopped(), sessionId: '', seq: 0));
      return;
    }
    final m = event.cast<String, dynamic>();
    final status = m['status'];
    final sid = m['sessionId'];
    final hasId = sid is String && sid.isNotEmpty;
    final rawSeq = m['seq'];
    final validSeq = rawSeq is int && rawSeq > 0;
    final isSnapshot = m['replay'] == true;

    // Explicit protocol special case: the identity-less initial Stopped.
    if (!hasId) {
      if (status == 'Stopped' && !validSeq) {
        out.add(CoreStatus.eventFrom(m));
      } else {
        print('[watchStatus] drop identity-less non-initial event: $status');
      }
      return;
    }

    if (isSnapshot) {
      // §4: a snapshot must not regress the anchor to a superseded session.
      if (_anchoredSessionId != null && _anchoredSessionId != sid) {
        print('[watchStatus] snapshot ignored: $sid != anchored $_anchoredSessionId (anchor kept)');
        return;
      }
      if (!validSeq) {
        print('[watchStatus] snapshot without a valid seq rejected: $sid');
        return;
      }
      _anchoredSessionId = sid;
      print('[watchStatus] event: ${CoreStatus.eventFrom(m)}');
      out.add(CoreStatus.eventFrom(m));
      return;
    }

    // §5.2: live events without a positive integer seq never publish.
    if (!validSeq) {
      print('[watchStatus] drop seq-less live event: $status session=$sid');
      return;
    }
    if (_anchoredSessionId == null) {
      print('[watchStatus] drop pre-receipt event session=$sid status=$status (await snapshot)');
      return;
    }
    if (sid != _anchoredSessionId) {
      print('[watchStatus] drop event of stale session=$sid (anchored=$_anchoredSessionId)');
      return;
    }
    final e = CoreStatus.eventFrom(m);
    print('[watchStatus] event: $e');
    out.add(e);
  }

  // ── Stubbed: node selection / stats / logs (P1-next) ──────────────────────
  // Signatures and types are stable; implementations are TODO.

  /// WO-6: single-node deployment → emit the ONE group once (contract pinned by
  /// test/r31c_node_group_test.dart). Emits null when no committed config identifies a
  /// node — the UI shows no node card rather than a fiction.
  Stream<OutboundGroupInfo?> watchGroup() {
    final config = _lastCommittedConfig;
    return Stream<OutboundGroupInfo?>.value(
      config == null ? null : NodeGroupBuilder.fromXrayConfig(config),
    );
  }

  Stream<List<OutboundGroupInfo>> watchActiveGroups() {
    final group = watchGroupSync();
    return Stream<List<OutboundGroupInfo>>.value(group == null ? const [] : [group]);
  }

  /// Same resolution as [watchGroup] without the stream wrapper (used by the list variant).
  @visibleForTesting
  OutboundGroupInfo? watchGroupSync() {
    final config = _lastCommittedConfig;
    return config == null ? null : NodeGroupBuilder.fromXrayConfig(config);
  }

  /// WO-5: real traffic stats. Kotlin pushes cumulative counters once per second while the
  /// tunnel is up; the rate math happens here (StatsRateCalculator, unit-tested). When the
  /// service is down the channel pushes nothing — StatsNotifier already renders idle via
  /// the serviceRunning gate, so this stream simply stays quiet.
  Stream<StatsInfo> watchStats() {
    final calc = StatsRateCalculator();
    return _statsChannel.receiveBroadcastStream().map((raw) {
      final map = (raw as Map).cast<Object?, Object?>();
      return calc.next(
        txBytes: (map['txBytes'] as int?) ?? 0,
        rxBytes: (map['rxBytes'] as int?) ?? 0,
        tsMs: (map['tsMs'] as int?) ?? 0,
      );
    }).handleError((Object e) {
      loggy.warning('[stats] channel error (ignored, UI keeps last value): $e');
    });
  }

  TaskEither<String, Unit> selectOutbound(String groupTag, String outboundTag) {
    // TODO(P1-next): node selection (needs dynamic node delivery first).
    return TaskEither.of(unit);
  }

  TaskEither<String, Unit> selectOutboundWithFallback(List<String> groupCandidates, List<String> tagCandidates) {
    // TODO(P1-next): see selectOutbound.
    return TaskEither.of(unit);
  }

  TaskEither<String, Unit> urlTest(String tag) {
    // urlTestDelay stays 0 → UI gracefully hides the delay indicator.
    // TODO(P1-next): real latency test once multiple nodes exist.
    return TaskEither.of(unit);
  }

  Stream<List<LogEntry>> watchLogs(String path) {
    // TODO(P1-next): real log stream from the core.
    return const Stream.empty();
  }

  TaskEither<String, Unit> clearLogs() {
    // TODO(P1-next): clear core logs.
    return TaskEither.of(unit);
  }

  /// No-op: the MethodChannel bridge has no persistent frontend connection to
  /// close (the old gRPC service used this to tear down its client).
  Future<void> closeFront() async {}
}
