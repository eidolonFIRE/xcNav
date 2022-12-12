import 'package:flutter_local_notifications/flutter_local_notifications.dart';

bool inFocus = false;

void setFocus(bool focused) {
  inFocus = focused;
}

void configLocalNotification() {
  var initializationSettingsAndroid = const AndroidInitializationSettings("@mipmap/ic_launcher");
  var initializationSettingsIOS = const DarwinInitializationSettings();
  var initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
  FlutterLocalNotificationsPlugin().initialize(initializationSettings);
}

void showNotification(String fromPilot, String message) async {
  // Don't show any notificaitons if we're already in focus
  if (inFocus) return;

  var androidPlatformChannelSpecifics = const AndroidNotificationDetails(
    'com.xcnav',
    'xcNav',
    channelDescription: 'message notification',
    playSound: true,
    enableVibration: true,
    importance: Importance.high,
    priority: Priority.high,
  );
  var iOSPlatformChannelSpecifics = const DarwinNotificationDetails();
  var platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics, iOS: iOSPlatformChannelSpecifics);
  await FlutterLocalNotificationsPlugin().show(
    0, "xcNav - $fromPilot",
    message, platformChannelSpecifics,
    // payload: jsonEncode(message)
  );
}
