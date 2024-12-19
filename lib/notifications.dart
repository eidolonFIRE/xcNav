import 'package:flutter_local_notifications/flutter_local_notifications.dart';

bool _inFocus = false;

// All possibly active notifications
final List<int> _notifications = [];

void setFocus(bool focused) {
  _inFocus = focused;
}

void configLocalNotification() {
  const initializationSettingsAndroid = AndroidInitializationSettings("@mipmap/ic_launcher");
  const initializationSettingsIOS = DarwinInitializationSettings();
  const initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
  FlutterLocalNotificationsPlugin().initialize(initializationSettings);
}

void tryClearAll() {
  for (final id in _notifications) {
    FlutterLocalNotificationsPlugin().cancel(id);
  }
  _notifications.clear();
}

void showNotification(String fromPilot, String message) async {
  // Don't show any notificaitons if we're already in focus
  if (_inFocus) return;

  const platformChannelSpecifics = NotificationDetails(
      android: AndroidNotificationDetails(
        'com.xcnav',
        'xcNav',
        channelDescription: 'message notification',
        playSound: true,
        enableVibration: true,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails());

  final id = _notifications.length;
  _notifications.add(id);

  await FlutterLocalNotificationsPlugin().show(
    id,
    "xcNav - $fromPilot",
    message,
    platformChannelSpecifics,
  );
}
