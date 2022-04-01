import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

bool inFocus = false;

void setFocus(bool focused) {
  inFocus = focused;
}

void configLocalNotification() {
  var initializationSettingsAndroid =
      const AndroidInitializationSettings("@mipmap/ic_launcher");
  var initializationSettingsIOS = const IOSInitializationSettings();
  var initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
  FlutterLocalNotificationsPlugin().initialize(initializationSettings);
}

void showNotification(message) async {
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
  var iOSPlatformChannelSpecifics = const IOSNotificationDetails();
  var platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics);
  await FlutterLocalNotificationsPlugin().show(
    0, "xcNav",
    message, platformChannelSpecifics,
    // payload: jsonEncode(message)
  );
}
