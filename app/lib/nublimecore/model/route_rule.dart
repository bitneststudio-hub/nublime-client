/// Lightweight route-rule model replacing the legacy protobuf `RouteRule` /
/// `Rule` / `Outbound` / `Network` / `Protocol` (route_rule.pb.dart + .pbenum).
///
/// Pure JSON serialization — no protobuf, no `package:protobuf` dependency.
/// Field numbering (1..18) and snake_case names match the old protobuf schema,
/// and fields are NON-NULL with defaults (like protobuf generated messages) so
/// the existing route-rules UI (`value.name`, `value.outbound`, …) keeps
/// working unchanged.
library;

import 'dart:convert';

class RouteRule {
  RouteRule({required this.rules});

  final List<Rule> rules;

  factory RouteRule.fromBuffer(List<int> bytes) =>
      RouteRule.fromJson(utf8.decode(bytes));

  factory RouteRule.fromJson(String json) {
    final decoded = jsonDecode(json);
    final rules = (decoded as Map<String, dynamic>)['rules'] as List<dynamic>? ?? [];
    return RouteRule(
      rules: rules.map((r) => Rule.fromJson(jsonEncode(r))).toList(),
    );
  }

  String writeToJson() => jsonEncode({
        'rules': rules.map((r) => r.toProto3Json()).toList(),
      });

  List<int> writeToBuffer() => utf8.encode(writeToJson());
}

/// Common interface for the route-rule enums, replacing protobuf's
/// `ProtobufEnum` (which the route-rules UI used for `value is ProtobufEnum`).
abstract interface class RouteEnumValue {
  int get value;
}

enum Outbound implements RouteEnumValue {
  proxy(0),
  direct(1),
  direct_with_fragment(2),
  block(3);

  const Outbound(this.value);

  @override
  final int value;
}

enum Network implements RouteEnumValue {
  all(0),
  tcp(1),
  udp(2);

  const Network(this.value);

  @override
  final int value;
}

enum Protocol implements RouteEnumValue {
  tls(0),
  http(1),
  quic(2),
  stun(3),
  dns(4),
  bittorrent(5);

  const Protocol(this.value);

  @override
  final int value;
}

class Rule {
  Rule({
    this.listOrder = 0,
    this.enabled = true,
    this.name = '',
    this.outbound = Outbound.direct,
    this.ruleSets = const [],
    this.packageNames = const [],
    this.processNames = const [],
    this.processPaths = const [],
    this.network = Network.all,
    this.portRanges = const [],
    this.sourcePortRanges = const [],
    this.protocols = const [],
    this.ipCidrs = const [],
    this.sourceIpCidrs = const [],
    this.domains = const [],
    this.domainSuffixes = const [],
    this.domainKeywords = const [],
    this.domainRegexes = const [],
  });

  // Non-null with defaults, mirroring protobuf generated-message semantics.
  int listOrder;
  bool enabled;
  String name;
  Outbound outbound;
  List<String> ruleSets;
  List<String> packageNames;
  List<String> processNames;
  List<String> processPaths;
  Network network;
  List<String> portRanges;
  List<String> sourcePortRanges;
  List<Protocol> protocols;
  List<String> ipCidrs;
  List<String> sourceIpCidrs;
  List<String> domains;
  List<String> domainSuffixes;
  List<String> domainKeywords;
  List<String> domainRegexes;

  // protobuf "presence" helpers (simplified: non-default = present).
  bool hasListOrder() => true;
  bool hasEnabled() => true;
  bool hasName() => name.isNotEmpty;
  bool hasOutbound() => true;

  /// protobuf-style field-number-indexed map (keys "1".."18"). Used by the
  /// notifier's `update` to read/modify a single field.
  Map<String, dynamic> writeToJsonMap() => {
        '1': listOrder,
        '2': enabled,
        '3': name,
        '4': outbound.name,
        '5': ruleSets,
        '6': packageNames,
        '7': processNames,
        '8': processPaths,
        '9': network.name,
        '10': portRanges,
        '11': sourcePortRanges,
        '12': protocols.map((e) => e.name).toList(),
        '13': ipCidrs,
        '14': sourceIpCidrs,
        '15': domains,
        '16': domainSuffixes,
        '17': domainKeywords,
        '18': domainRegexes,
      };

  /// snake_case JSON map (proto3-json style).
  Map<String, dynamic> toProto3Json() => {
        'list_order': listOrder,
        'enabled': enabled,
        'name': name,
        'outbound': outbound.name,
        'rule_sets': ruleSets,
        'package_names': packageNames,
        'process_names': processNames,
        'process_paths': processPaths,
        'network': network.name,
        'port_ranges': portRanges,
        'source_port_ranges': sourcePortRanges,
        'protocols': protocols.map((e) => e.name).toList(),
        'ip_cidrs': ipCidrs,
        'source_ip_cidrs': sourceIpCidrs,
        'domains': domains,
        'domain_suffixes': domainSuffixes,
        'domain_keywords': domainKeywords,
        'domain_regexes': domainRegexes,
      };

  static Outbound _outboundFrom(Object? v) => Outbound.values.firstWhere(
        (e) => e.name == v || e.value.toString() == v.toString(),
        orElse: () => Outbound.direct,
      );
  static Network _networkFrom(Object? v) => Network.values.firstWhere(
        (e) => e.name == v || e.value.toString() == v.toString(),
        orElse: () => Network.all,
      );
  static List<Protocol> _protocolsFrom(List<dynamic>? l) => (l ?? const [])
      .map((e) => Protocol.values.firstWhere(
            (p) => p.name == e || p.value.toString() == e.toString(),
            orElse: () => Protocol.tls,
          ))
      .toList();

  /// Parse from either a field-number map (writeToJsonMap output) or a
  /// snake_case map (toProto3Json output).
  factory Rule.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    String? g(String k) => map[k] as String?;
    List<dynamic>? l(String k) => map[k] as List<dynamic>?;
    bool? b(String k) => map[k] as bool?;
    int? i(String k) => map[k] as int?;

    List<String> sl(String k1, String k2) =>
        (l(k1) ?? l(k2))?.cast<String>() ?? const [];

    return Rule(
      listOrder: i('1') ?? i('list_order') ?? 0,
      enabled: b('2') ?? b('enabled') ?? true,
      name: g('3') ?? g('name') ?? '',
      outbound: _outboundFrom(g('4') ?? g('outbound')),
      ruleSets: sl('5', 'rule_sets'),
      packageNames: sl('6', 'package_names'),
      processNames: sl('7', 'process_names'),
      processPaths: sl('8', 'process_paths'),
      network: _networkFrom(g('9') ?? g('network')),
      portRanges: sl('10', 'port_ranges'),
      sourcePortRanges: sl('11', 'source_port_ranges'),
      protocols: _protocolsFrom(l('12') ?? l('protocols')),
      ipCidrs: sl('13', 'ip_cidrs'),
      sourceIpCidrs: sl('14', 'source_ip_cidrs'),
      domains: sl('15', 'domains'),
      domainSuffixes: sl('16', 'domain_suffixes'),
      domainKeywords: sl('17', 'domain_keywords'),
      domainRegexes: sl('18', 'domain_regexes'),
    );
  }
}
