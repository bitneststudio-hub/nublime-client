// R2-6 (deployment spec §5 P2, "旧用户数据迁移"): the pre-rebuild app and the production
// activation backend deliver node profiles in sing-box wire format; the Xray core and
// its schema validator (validateXrayConfigContent, R02 / Astra 10-09 §4.2) accept only
// the Xray wire shape. This converter is the ONE in-memory bridge between the two.
//
// Discipline (mirrors R02's "ONE validator"):
//   - ONE conversion entry: effectiveXrayContent(). Every delivery-chain site (read,
//     preview, commit — in NuBLimeCoreService) calls it; no call site may inline its
//     own shape sniffing or field extraction.
//   - Lazy & idempotent: the READ paths never rewrite the stored profile file. The
//     converted document is not sing-box-shaped, so converting again is a no-op; the
//     only site that persists is the commit path, and it persists the result.
//   - Fail-closed: any missing critical node field rejects the WHOLE conversion with
//     an explicit reason — a half-converted config must never reach the core, and a
//     broken route.final must never silently select a different node than the backend
//     chose.
//
// Input contract = the production renderer's actual output (04_服务端部署_脱敏/
// 历史_已废弃/app.routes.js, generateSingboxConfig): outbounds[] of `type`-keyed
// entries — one `vless` outbound per node (server / server_port / uuid / flow /
// tls.server_name / tls.reality.public_key / tls.reality.short_id), `hysteria2`
// outbounds, and a `selector` whose `default` names the node to dial. Hysteria2 is out
// of P2 scope: hy2 nodes are never selected and never emitted.

import 'dart:convert';

import 'package:fpdart/fpdart.dart';

/// Conversion outcome: Left carries the human-readable rejection reason, Right the
/// effective (Xray-shaped) config content.
typedef XrayContentResult = Either<String, String>;

/// A validated, dial-able vless+Reality node extracted from a legacy box document.
typedef VlessNode = ({
  String address,
  int port,
  String uuid,
  String sni,
  String publicKey,
  String shortId,
  String flow,
  /// 'tcp' (REALITY+Vision, the primary path) or 'xhttp' (REALITY+XHTTP fallback).
  String transport,
  /// XHTTP request path; empty for tcp.
  String xhttpPath,
});

/// The ONE sing-box → Xray migration entry for the whole delivery chain.
///
/// Static and pure on purpose: the same class serves the read paths (start/restart,
/// preview) and the commit path (validateConfigByPath), and is directly unit-testable
/// without a service instance.
class SingboxXrayConverter {
  SingboxXrayConverter._();

  /// True when [decoded] carries legacy box-style outbounds: entries keyed by `type`
  /// (an Xray outbound is keyed by `protocol`).
  ///
  /// Mirrors the shape discriminator inside validateXrayConfigContent — never widen
  /// one side without the other.
  static bool looksLikeSingboxConfig(Map<dynamic, dynamic> decoded) {
    final outbounds = decoded['outbounds'];
    if (outbounds is! List) return false;
    for (final dynamic ob in outbounds) {
      if (ob is Map && ob.containsKey('type') && !ob.containsKey('protocol')) {
        return true;
      }
    }
    return false;
  }

  /// The ONE conversion entry used by the whole delivery chain.
  ///
  /// Returns the ORIGINAL content unchanged (Right) when it is not sing-box-shaped —
  /// Xray documents pass through byte-identical. Call sites must treat the result as
  /// "effective content" for validation and downstream consumption, never as an
  /// instruction to rewrite the stored file (only the commit path persists, and it
  /// persists exactly this result).
  static XrayContentResult effectiveXrayContent(
    String content, {
    required String fingerprint,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (e) {
      return left('profile content is not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      return left('profile content is not a config JSON object');
    }
    if (!looksLikeSingboxConfig(decoded)) return right(content);
    return _convert(decoded, fingerprint: fingerprint);
  }

  static XrayContentResult _convert(Map<dynamic, dynamic> config,
      {required String fingerprint}) {
    final outbounds = config['outbounds'];
    if (outbounds is! List || outbounds.isEmpty) {
      return left('legacy-box profile carries no outbounds');
    }
    return _selectVlessNode(config, outbounds)
        .map((node) => _emitXrayConfig(node, fingerprint: fingerprint));
  }

  // ------------------------------------------------------------------ node selection

  /// Chooses the dial-able node, deterministically and fail-closed:
  ///
  /// 1. `route.final` names the outbound the backend dials. It may name a `selector`
  ///    (production shape: final='select') — the selector's `default` (or, absent a
  ///    default, its first entry) names the node.
  /// 2. The resolved outbound must be a vless+Reality node; any other type (e.g.
  ///    hysteria2) or any broken reference is an EXPLICIT rejection — the converter
  ///    never falls back to a different node than the backend selected.
  /// 3. A PRESENT-but-malformed route (route not an object, or `final` present but
  ///    not a string tag) is likewise rejected explicitly (R27-F2, closed with B-3).
  ///    sing-box keeps `route.final` OPTIONAL, so a well-formed route object without
  ///    `final` — or no route at all — falls to the deterministic scan branch: the
  ///    first vless+Reality outbound. The production renderer always emits
  ///    route.final, so this branch serves hand-shaped documents only.
  static Either<String, VlessNode> _selectVlessNode(
      Map<dynamic, dynamic> config, List outbounds) {
    final route = config['route'];
    if (route != null && route is! Map) {
      return left(
          'route must be an object when present — refusing to guess a node');
    }
    if (route is Map && route['final'] is String) {
      var wanted = route['final'] as String;
      var ob = _byTag(outbounds, wanted);
      if (ob == null) {
        return left(
            'route.final references missing outbound "$wanted" — refusing to guess a node');
      }
      if (ob['type'] == 'selector') {
        final selDefault = ob['default'];
        final selOutbounds = ob['outbounds'];
        if (selDefault is String) {
          wanted = selDefault;
        } else if (selOutbounds is List &&
            selOutbounds.isNotEmpty &&
            selOutbounds.first is String) {
          wanted = selOutbounds.first as String;
        } else {
          return left(
              'selector "$wanted" names no default and no outbounds — refusing to guess a node');
        }
        ob = _byTag(outbounds, wanted);
        if (ob == null) {
          return left(
              'selector resolves to missing outbound "$wanted" — refusing to guess a node');
        }
      }
      final node = _asVlessRealityNode(ob);
      if (node == null) {
        return left(
            'route.final resolves to outbound "$wanted" which is not a vless node '
            '(hysteria2 is not dial-able by the Xray core in P2 scope)');
      }
      return node;
    }
    if (route is Map && route['final'] != null) {
      // route exists, `final` is present but not a string tag (R27-F2).
      return left(
          'route.final must be a string tag when present — refusing to guess a node');
    }
    // No usable route.final: scan for the first vless+Reality outbound.
    Either<String, VlessNode>? firstFailure;
    for (final dynamic candidate in outbounds) {
      final node = _asVlessRealityNode(candidate);
      if (node == null) continue;
      if (node.isRight()) return node;
      firstFailure ??= node;
    }
    if (firstFailure != null) {
      return firstFailure;
    }
    return left('legacy-box profile has no vless outbound to migrate');
  }

  static Map<dynamic, dynamic>? _byTag(List outbounds, String tag) {
    for (final dynamic ob in outbounds) {
      if (ob is Map && ob['tag'] == tag) return ob;
    }
    return null;
  }

  // --------------------------------------------------------------------- node checks

  /// Validates one outbound as a dial-able vless+Reality node.
  ///
  /// Returns null when [ob] is not a vless candidate at all (caller keeps scanning);
  /// a non-null result is either the validated node (Right) or an explicit field-level
  /// rejection (Left). Uses a private control-flow exception so every critical field
  /// check is a plain `if (bad) throw _Reject(...)`.
  static Either<String, VlessNode>? _asVlessRealityNode(Map<dynamic, dynamic> ob) {
    if (ob['type'] != 'vless') return null;
    final tag = ob['tag'] is String ? ob['tag'] as String : 'untagged-vless';
    try {
      final address = _requireNonEmpty(ob, 'server', tag);
      final uuid = _requireNonEmpty(ob, 'uuid', tag);
      final port = _requirePort(ob, tag);

      final tls = ob['tls'];
      if (tls is! Map || tls['enabled'] != true) {
        throw const _Reject('tls.enabled must be true (a Reality node is required)');
      }
      final sni = _requireNonEmpty(tls, 'server_name', tag);
      final reality = tls['reality'];
      if (reality is! Map || reality['enabled'] != true) {
        throw const _Reject('tls.reality.enabled must be true (a Reality node is required)');
      }
      final publicKey = _requireNonEmpty(reality, 'public_key', tag);
      final shortIdValue = reality['short_id'];
      if (shortIdValue is! String) {
        // Empty string is legal for Reality; missing/non-string is not.
        throw const _Reject('tls.reality.short_id must be a string (empty is allowed)');
      }
      // Transport (2026-10-28): the backend may deliver an XHTTP fallback node. Unknown values are
      // rejected rather than coerced — a profile the kernel cannot dial is worse than a clear error.
      final transportRaw = ob['xray_transport'];
      final transport =
          (transportRaw is String && transportRaw.trim().isNotEmpty)
              ? transportRaw.trim().toLowerCase()
              : 'tcp';
      if (transport != 'tcp' && transport != 'xhttp') {
        throw _Reject('unsupported xray_transport "$transportRaw"');
      }
      var xhttpPath = '';
      if (transport == 'xhttp') {
        final rawPath = ob['xray_xhttp_path'];
        if (rawPath is! String || rawPath.trim().isEmpty) {
          throw const _Reject('xray_xhttp_path missing for xhttp transport');
        }
        xhttpPath = rawPath.trim();
        if (!xhttpPath.startsWith('/') || xhttpPath.contains(' ')) {
          throw const _Reject('xray_xhttp_path malformed (must start with "/")');
        }
      }
      var flowValue = ob['flow'];
      // Vision flow is a raw-transport feature; XHTTP must not carry it.
      final flow = transport == 'xhttp'
          ? ''
          : (flowValue is String && flowValue.trim().isNotEmpty)
              ? flowValue
              : 'xtls-rprx-vision';

      return right((
        address: address,
        port: port,
        uuid: uuid,
        sni: sni,
        publicKey: publicKey,
        shortId: shortIdValue,
        flow: flow,
        transport: transport,
        xhttpPath: xhttpPath,
      ));
    } on _Reject catch (r) {
      return left('legacy-box vless outbound "$tag": ${r.message}');
    }
  }

  static String _requireNonEmpty(
      Map<dynamic, dynamic> m, String key, String tag) {
    final v = m[key];
    if (v is String && v.trim().isNotEmpty) return v;
    throw _Reject('missing or empty "$key"');
  }

  static int _requirePort(Map<dynamic, dynamic> ob, String tag) {
    final p = ob['server_port'];
    if (p is num && p == p.round() && p >= 1 && p <= 65535) return p.toInt();
    throw const _Reject('"server_port" must be an integer in 1..65535');
  }

  // ----------------------------------------------------------------------- emission

  /// Emits the Xray wire document for a validated node. The structure mirrors the
  /// built-in single-node template (NuBLimeCoreService._defaultXrayConfig) exactly:
  /// one `proxy` vless outbound with Reality stream settings, an empty `inbounds`
  /// (the Android side injects the authenticated SOCKS inbound), and the socks-in →
  /// proxy routing rule the hev feeding path relies on.
  static String _emitXrayConfig(VlessNode node,
      {required String fingerprint}) {
    final config = <String, dynamic>{
      'log': const <String, dynamic>{'loglevel': 'debug'},
      'inbounds': const <dynamic>[],
      'outbounds': <dynamic>[
        <String, dynamic>{
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': <String, dynamic>{
            'vnext': <dynamic>[
              <String, dynamic>{
                'address': node.address,
                'port': node.port,
                'users': <dynamic>[
                  <String, dynamic>{
                    'id': node.uuid,
                    'encryption': 'none',
                    if (node.flow.isNotEmpty) 'flow': node.flow,
                  },
                ],
              },
            ],
          },
          'streamSettings': <String, dynamic>{
            'network': node.transport,
            'security': 'reality',
            'realitySettings': <String, dynamic>{
              'serverName': node.sni,
              'publicKey': node.publicKey,
              'shortId': node.shortId,
              'fingerprint': fingerprint,
            },
            if (node.transport == 'xhttp')
              'xhttpSettings': <String, dynamic>{
                'path': node.xhttpPath,
                'mode': 'auto',
              },
          },
        },
      ],
      'routing': <String, dynamic>{
        'domainStrategy': 'AsIs',
        'rules': <dynamic>[
          <String, dynamic>{
            'type': 'field',
            'inboundTag': <String>['socks-in'],
            'network': 'tcp,udp',
            'outboundTag': 'proxy',
          },
        ],
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }
}

/// Private control-flow exception: carries the field-level rejection reason.
class _Reject implements Exception {
  const _Reject(this.message);
  final String message;
}
