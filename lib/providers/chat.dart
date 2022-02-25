import 'package:flutter/material.dart';

// --- Models
import 'package:xcnav/models/message.dart';

class Chat with ChangeNotifier {
  List<Message> messages = [];

  processMessageFromServer(dynamic msg) {
    messages.add(Message(
        msg["timestamp"], msg["pilot_id"], msg["text"], msg["emergency"]));
    notifyListeners();
  }
}
