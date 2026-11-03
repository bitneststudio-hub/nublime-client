/// Core connection status for the Xray-based VPN core.
///
/// Replaces `singbox/model/core_status.dart` (legacy core remnants).
/// The old version depended on hcore protobuf (CoreInfoResponse/MessageType);
/// this version is a pure Dart sealed class, fed by the MethodChannel status
/// stream instead of gRPC CoreInfoResponse.
///
/// The connection state machine maps these to UI states:
///   CoreStopped  -> Disconnected
///   CoreStarting -> Connecting
///   CoreStarted  -> Connected
///   CoreStopping -> Disconnecting
library;

import 'package:nublime/features/connection/model/connection_failure.dart';

sealed class CoreStatus {
  const CoreStatus();

  /// Parse a status map coming from the Android MethodChannel.
  ///
  /// Expected shape: `{"status": "Stopped"|"Starting"|"Started"|"Stopping",
  ///                    "alert": <optional string>, "message": <optional string>}`
  factory CoreStatus.fromEvent(Map<String, dynamic>? event) {
    switch (event?['status']) {
      case 'Stopped':
        final alertStr = event?['alert'] as String?;
        // R01 §5.2: prefer the native errorCode (e.g. PROBE_FAILED / HEALTH_LOST / EXPLICIT_FAILURE)
        // over a generic alert string, so the failure reason survives to the UI.
        final errorCode = event?['errorCode'] as String?;
        var message = event?['message'] as String?;
        if (message == null && errorCode != null && errorCode.isNotEmpty) message = errorCode;
        var alert = _parseAlert(alertStr);
        if (alert == null && (alertStr ?? '').isNotEmpty) {
          message = (message ?? '').isNotEmpty ? '$alertStr: $message' : alertStr;
        }
        return CoreStopped(alert: alert, message: message);
      case 'Starting':
        return const CoreStarting();
      case 'Started':
        return const CoreStarted();
      case 'Stopping':
        return const CoreStopping();
      default:
        // R01: a stale/unknown phase must not crash the status bridge.
        // Fail safe (never surfaces as Connected): stopped + unknown alert.
        return CoreStopped(
          alert: CoreAlert.unknown,
          message: 'unexpected status [${event?['status']}]',
        );
    }
  }

  /// Convert this status into a [ConnectionFailure] if the core reported an
  /// error alert that should surface as a connection failure.
  ConnectionFailure? getCoreAlert() => switch (this) {
        CoreStopped(alert: final alert, message: final message) when alert != null =>
          switch (alert) {
            CoreAlert.emptyConfiguration => ConnectionFailure.invalidConfig(message),
            CoreAlert.requestVPNPermission => ConnectionFailure.missingVpnPermission(message),
            CoreAlert.requestNotificationPermission =>
              ConnectionFailure.missingNotificationPermission(message),
            _ => ConnectionFailure.unexpected('${alert.name} - $message'),
          },
        _ => null,
      };

  /// §7-3: build a [CoreEvent] from the bridge payload, validating field types.
  static CoreEvent eventFrom(Map<String, dynamic>? event) => CoreEvent(
        status: CoreStatus.fromEvent(event),
        sessionId: event?['sessionId'] is String ? event!['sessionId'] as String : '',
        seq: event?['seq'] is int ? event!['seq'] as int : 0,
      );

  static CoreAlert? _parseAlert(String? s) {
    if (s == null || s.isEmpty) return null;
    return switch (s.toLowerCase()) {
      'requestvpnpermission' || 'request_vpn_permission' => CoreAlert.requestVPNPermission,
      'requestnotificationpermission' || 'request_notification_permission' =>
        CoreAlert.requestNotificationPermission,
      'emptyconfiguration' || 'empty_configuration' => CoreAlert.emptyConfiguration,
      _ => CoreAlert.unknown,
    };
  }
}

/// A status event plus the session identity and monotonic sequence that produced it.
///
/// Consumers must use [sessionId]/[seq] to drop stale or out-of-order events —
/// carrying the fields without consuming them is not isolation (Astra R01 §4.3).
class CoreEvent {
  const CoreEvent({required this.status, required this.sessionId, required this.seq});

  final CoreStatus status;
  final String sessionId;
  final int seq;

  @override
  String toString() => 'CoreEvent(${status.runtimeType}, session=$sessionId, seq=$seq)';
}

final class CoreStopped extends CoreStatus {
  const CoreStopped({this.alert, this.message});

  final CoreAlert? alert;
  final String? message;
}

final class CoreStarting extends CoreStatus {
  const CoreStarting();
}

final class CoreStarted extends CoreStatus {
  const CoreStarted();
}

final class CoreStopping extends CoreStatus {
  const CoreStopping();
}

/// Error alerts the core can report, narrowed to what the Xray-based core
/// actually surfaces (VPN/notification permission and config problems).
enum CoreAlert {
  requestVPNPermission,
  requestNotificationPermission,
  emptyConfiguration,
  unknown,
}
