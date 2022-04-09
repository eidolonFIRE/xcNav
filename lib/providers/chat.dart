import 'package:flutter/material.dart';

// --- Models
import 'package:xcnav/models/message.dart';
import 'package:xcnav/notifications.dart';

class Chat with ChangeNotifier {
  List<Message> messages = [];

  int chatLastOpened = 0;
  int numUnread = 0;

  void leftGroup() {
    messages.clear();
    notifyListeners();
  }

  void processMessageFromServer(dynamic msg) {
    Message newMsg = Message(DateTime.now().millisecondsSinceEpoch,
        msg["pilot_id"], msg["text"], msg["emergency"]);
    messages.add(newMsg);
    numUnread++;

    showNotification(msg["text"]);

    notifyListeners();
  }

  void processSentMessage(
      int timestamp, String pilotID, String text, bool isEmergency) {
    messages.add(Message(timestamp, pilotID, text, isEmergency));
    notifyListeners();
  }
}
