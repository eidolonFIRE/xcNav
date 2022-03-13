import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final bool isMe;
  final String text;
  final Widget user;

  const ChatBubble(this.isMe, this.text, this.user, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.start : MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          // mainAxisSize: MainAxisSize.min,
          mainAxisSize: MainAxisSize.max,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.8),
              child: Card(
                color: isMe ? Colors.blue : Colors.white60,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(10),
                        bottomLeft: isMe
                            ? const Radius.circular(1)
                            : const Radius.circular(10),
                        topRight: const Radius.circular(10),
                        bottomRight: isMe
                            ? const Radius.circular(10)
                            : const Radius.circular(1))),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    text,
                    maxLines: 15,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: const TextStyle(fontSize: 18, color: Colors.black),
                  ),
                ),
              ),
            ),
            isMe ? Container() : Positioned(right: 0, bottom: 0, child: user)
          ]),
    );
  }
}
