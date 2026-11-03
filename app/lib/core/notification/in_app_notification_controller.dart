import 'package:flutter/material.dart';
import 'package:nublime/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:toastification/toastification.dart';

part 'in_app_notification_controller.g.dart';

@Riverpod(keepAlive: true)
InAppNotificationController inAppNotificationController(Ref ref) {
  return InAppNotificationController();
}

enum NotificationType { info, error, success }

class InAppNotificationController with AppLogger {
  /// Track whether an overlay/notification is currently showing
  bool _isOverlayShowing = false;
  
  /// Track the currently active notification item
  ToastificationItem? _activeNotification;

  /// Check if overlay is ready to show a new notification
  bool get isOverlayReady => !_isOverlayShowing;
  
  /// Get the currently active notification
  ToastificationItem? get activeNotification => _activeNotification;

  ToastificationItem? _show(
    String message, {
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    // Check if overlay is already showing to prevent stacking
    if (_isOverlayShowing) {
      loggy.debug('Overlay already showing, dismissing previous notification');
      toastification.dismissAll();
      _isOverlayShowing = false;
      _activeNotification = null;
    }
    
    try {
      _isOverlayShowing = true;
      _activeNotification = toastification.show(
        title: Text(message),
        type: type._toastificationType,
        alignment: AlignmentDirectional.bottomStart,
        autoCloseDuration: duration,
        style: ToastificationStyle.fillColored,
        pauseOnHover: true,
        showProgressBar: false,
        dragToClose: true,
        closeOnClick: true,
        closeButtonShowType: CloseButtonShowType.onHover,
      );
      loggy.debug('Notification shown: $message');
      return _activeNotification;
    } catch (e, stackTrace) {
      loggy.error('Failed to show notification', e, stackTrace);
      _isOverlayShowing = false;
      _activeNotification = null;
      return null;
    }
  }

  /// Show error toast with overlay state check
  ToastificationItem? showErrorToast(String message) {
    if (!isOverlayReady) {
      loggy.debug('Overlay not ready, skipping error toast');
    }
    return _show(message, type: NotificationType.error, duration: const Duration(seconds: 5));
  }

  /// Show success toast with overlay state check
  ToastificationItem? showSuccessToast(String message) {
    if (!isOverlayReady) {
      loggy.debug('Overlay not ready, skipping success toast');
    }
    return _show(message, type: NotificationType.success);
  }

  /// Show info toast with overlay state check
  ToastificationItem? showInfoToast(String message, {Duration duration = const Duration(seconds: 3)}) {
    if (!isOverlayReady) {
      loggy.debug('Overlay not ready, skipping info toast');
    }
    return _show(message, duration: duration);
  }

  /// Manually dismiss the current notification
  void dismissCurrent() {
    if (_activeNotification != null) {
      toastification.dismiss(_activeNotification!);
      _isOverlayShowing = false;
      _activeNotification = null;
      loggy.debug('Notification manually dismissed');
    }
  }

  /// Dismiss all notifications
  void dismissAll() {
    toastification.dismissAll();
    _isOverlayShowing = false;
    _activeNotification = null;
    loggy.debug('All notifications dismissed');
  }
}

extension NotificationTypeX on NotificationType {
  ToastificationType get _toastificationType => switch (this) {
    NotificationType.success => ToastificationType.success,
    NotificationType.error => ToastificationType.error,
    NotificationType.info => ToastificationType.info,
  };
}
