/// Lightweight data models for the Xray-based core.
///
/// These replace the legacy core remnants (`singbox/model/*` and the
/// protobuf types `SystemInfo`/`OutboundGroup`/`LogMessage` from hcore.pb.dart).
/// They are PURE data shells — field shapes are designed to match what the
/// real data will look like when node selection / stats / logs are implemented
/// in a later P1 step, so callers don't need a second migration.
///
/// For now the stats / groups / logs methods are stubbed (TODO in the service);
/// these types exist so the stubs compile and the UI has a stable shape.
library;

import 'package:nublime/features/proxy/model/ip_info_entity.dart';

class StatsInfo {
  const StatsInfo({
    this.connectionsIn = 0,
    this.connectionsOut = 0,
    this.uplink = 0,
    this.downlink = 0,
    this.uplinkTotal = 0,
    this.downlinkTotal = 0,
  });

  final int connectionsIn;
  final int connectionsOut;
  final int uplink; // bytes/s (current)
  final int downlink; // bytes/s (current)
  final int uplinkTotal; // bytes (cumulative)
  final int downlinkTotal; // bytes (cumulative)

  /// protobuf-parity: old code called `SystemInfo.create()` for an empty instance.
  static StatsInfo create() => const StatsInfo();

  static const empty = StatsInfo();
}

/// A node group (single-node deployment → exactly one group with one item).
class OutboundGroupInfo {
  OutboundGroupInfo({
    required this.tag,
    required this.type,
    required this.selected,
    this.items = const [],
  });

  final String tag;
  final String type;
  String selected;
  final List<OutboundGroupItemInfo> items;
}

/// A node (outbound). Field shape matches the old protobuf `OutboundInfo` so
/// the proxy detail dialog keeps working without a second migration.
class OutboundGroupItemInfo {
  OutboundGroupItemInfo({
    this.tag = '',
    this.type = '',
    this.urlTestDelay = 0,
    this.urlTestTime,
    this.ipinfo,
    this.upload = 0,
    this.download = 0,
    this.isSelected = false,
    this.isGroup = false,
    this.isSecure = false,
    this.port = 0,
    this.host = '',
    this.groupSelectedTag = '',
  });

  final String tag;
  final String type;

  /// Delay in ms; 0 = unknown / not tested. UI treats 0 as "don't show".
  final int urlTestDelay;
  final DateTime? urlTestTime;

  /// IP info (nullable).
  final IpInfo? ipinfo;

  final int upload;
  final int download;
  bool isSelected;
  final bool isGroup;
  final bool isSecure;
  final int port;
  final String host;
  final String groupSelectedTag;

  /// Display tag with the `§…` suffix stripped.
  String get tagDisplay => tag.replaceFirst(RegExp(r'§[^§]*$'), '').trimRight();

  /// Selected-tag display for grouped outbounds.
  String get groupSelectedTagDisplay => groupSelectedTag;
}

/// A single log entry. Maps to the future "watchLogs" stream event.
class LogEntry {
  const LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
  });

  final String level; // "info" | "warning" | "error" | "debug"
  final String message;
  final DateTime timestamp;
}
