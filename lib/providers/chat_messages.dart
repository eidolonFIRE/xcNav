import 'package:flutter/material.dart';

// --- Models
import 'package:xcnav/models/message.dart';
import 'package:xcnav/notifications.dart';

class ChatMessages with ChangeNotifier {
  List<Message> messages = [];

  int chatLastOpened = 0;
  int numUnread = 0;

  void refresh() {
    notifyListeners();
  }

  void leftGroup() {
    messages.clear();
    notifyListeners();
  }

  void markAllRead(bool refresh) {
    chatLastOpened = DateTime.now().millisecondsSinceEpoch;
    numUnread = 0;
    if (refresh) notifyListeners();
  }

  void processMessageFromServer(String pilotName, dynamic msg) {
    Message newMsg = Message(DateTime.now().millisecondsSinceEpoch,
        msg["pilot_id"], msg["text"], msg["emergency"]);
    messages.add(newMsg);
    numUnread++;

    showNotification(pilotName, msg["text"] ?? "");

    notifyListeners();
  }

  void processSentMessage(
      int timestamp, String pilotID, String text, bool isEmergency) {
    messages.add(Message(timestamp, pilotID, text, isEmergency));
    notifyListeners();
  }
}
