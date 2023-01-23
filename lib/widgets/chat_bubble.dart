import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/providers/chat_messages.dart';

class ChatBubble extends StatelessWidget {
  final bool isMe;
  final String? pilotName;
  final String text;
  final Widget user;
  final int? timestamp;
  final double? maxWidth;

  const ChatBubble(this.isMe, this.text, this.user, this.pilotName, this.timestamp, {Key? key, this.maxWidth})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: GestureDetector(
        onTap: () => Provider.of<ChatMessages>(context, listen: false).markAllRead(true),
        child: Column(
          children: [
            Row(
                mainAxisAlignment: isMe ? MainAxisAlignment.start : MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.max,
                children: [
                  ConstrainedBox(
                    constraints:
                        BoxConstraints(minWidth: 30, maxWidth: maxWidth ?? (MediaQuery.of(context).size.width - 100)),
                    child: Card(
                      color: text.toLowerCase().startsWith("emergency:")
                          ? Colors.red
                          : (isMe ? Colors.blue.shade300 : const Color.fromARGB(255, 230, 230, 230)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(10),
                              bottomLeft: isMe ? const Radius.circular(1) : const Radius.circular(10),
                              topRight: const Radius.circular(10),
                              bottomRight: isMe ? const Radius.circular(10) : const Radius.circular(1))),
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Text(
                          text,
                          maxLines: 15,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: const TextStyle(fontSize: 22, color: Colors.black),
                        ),
                      ),
                    ),
                  ),

                  // --- Sender avatar image
                  if (!isMe) user,
                ]),
            Padding(
              padding: const EdgeInsets.only(left: 50, right: 50),
              child: Row(
                mainAxisAlignment: isMe ? MainAxisAlignment.start : MainAxisAlignment.end,
                children: [
                  if (pilotName != null)
                    Text(
                      pilotName!,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  if (pilotName != null && timestamp != null)
                    const SizedBox(
                      width: 20,
                    ),
                  if (timestamp != null)
                    Text(
                      "${Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - timestamp!).inMinutes}m",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
