import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_notification_service.dart';

/// A chat photo or video being sent, in the phone's notification bar: a
/// quiet notification with a progress bar that follows the upload (fast on
/// good signal, slow on weak), removed as soon as it is sent or fails. It
/// shows even with the app in the background. Android only: an iPhone has
/// no progress notifications, and the chat shows the progress either way.
class UploadProgressNotification {
  UploadProgressNotification({required this.title});

  /// e.g. "Sending video to Junior Pesigan".
  final String title;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'agritrade_uploads',
    'AgriTrade+ Uploads',
    description: 'Photos and videos you are sending in a chat',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  // One upload at a time (the chat sends one attachment at a time), so one
  // id; a new upload replaces any leftover.
  static const int _id = 7302;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  int _lastShown = -1;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// How far along, 0 to 1. Updates the bar in steps of 5% — the phone
  /// limits how often a notification may change.
  Future<void> update(double progress) async {
    if (!_supported) return;
    final percent = (progress * 100).clamp(0, 100).floor();
    if (percent != 100 && percent - _lastShown < 5 && _lastShown >= 0) return;
    _lastShown = percent;
    try {
      if (!_ready) {
        await PushNotificationService().prepareLocalNotifications();
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(_channel);
        _ready = true;
      }
      await _plugin.show(
        id: _id,
        title: title,
        body: percent >= 100 ? 'Finishing…' : '$percent%',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.low,
            priority: Priority.low,
            showProgress: true,
            maxProgress: 100,
            progress: percent,
            onlyAlertOnce: true,
            ongoing: true,
            autoCancel: false,
            silent: true,
          ),
        ),
      );
    } catch (_) {
      // Notifications are off or unavailable: the chat still shows it.
    }
  }

  /// The upload is over (sent, or failed): the notification goes away.
  Future<void> close() async {
    if (!_supported) return;
    try {
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }
}
