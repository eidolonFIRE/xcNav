import 'package:flutter/material.dart';

// --- Models
import 'package:xcnav/models/message.dart';

class Chat with ChangeNotifier {
  List<Message> messages = [];
  List<Message> notifyBubbles = [];

  int chatLastOpened = 0;

  void leftGroup() {
    messages.clear();
    notifyListeners();
  }

  void processMessageFromServer(dynamic msg) {
    // TODO: should we be using the real timestamp?
    Message newMsg = Message(DateTime.now().millisecondsSinceEpoch,
        msg["pilot_id"], msg["text"], msg["emergency"]);

    messages.add(newMsg);

    notifyListeners();
  }

  void processSentMessage(
      int timestamp, String pilotID, String text, bool isEmergency) {
    messages.add(Message(timestamp, pilotID, text, isEmergency));
    notifyListeners();
  }
}
