import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final bool isMe;
  final String text;
  final Widget user;

  ChatBubble(this.isMe, this.text, this.user, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isMe ? Colors.blue : Colors.white60,
      child: Text(text),
    );
  }
}
