import 'package:flutter/material.dart';

// --- Models
import 'package:xcnav/models/message.dart';

class Chat with ChangeNotifier {
  List<Message> messages = [];

  void leftGroup() {
    messages.clear();
    notifyListeners();
  }

  void processMessageFromServer(dynamic msg) {
    messages.add(Message(
        msg["timestamp"], msg["pilot_id"], msg["text"], msg["emergency"]));
    notifyListeners();
  }

  void processSentMessage(
      int timestamp, String pilotID, String text, bool isEmergency) {
    messages.add(Message(timestamp, pilotID, text, isEmergency));
    notifyListeners();
  }
}
