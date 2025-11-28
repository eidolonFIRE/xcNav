import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:selectable_autolink_text/selectable_autolink_text.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xcnav/providers/chat_messages.dart';

class ChatBubble extends StatelessWidget {
  final bool isMe;
  final bool rightSide;
  final String? pilotName;
  final String text;
  final Widget user;
  final int? timestamp;
  final double? maxWidth;

  const ChatBubble(this.isMe, this.rightSide, this.text, this.user, this.pilotName, this.timestamp,
      {super.key, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: GestureDetector(
        onTap: () => Provider.of<ChatMessages>(context, listen: false).markAllRead(true),
        child: Column(
          children: [
            Row(
                mainAxisAlignment: !rightSide ? MainAxisAlignment.start : MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.max,
                children: [
                  if (!isMe && !rightSide) user,
                  ConstrainedBox(
                    constraints:
                        BoxConstraints(minWidth: 30, maxWidth: maxWidth ?? (MediaQuery.of(context).size.width - 100)),
                    child: Card(
                      color: text.toLowerCase().startsWith("emergency:")
                          ? Colors.red
                          : (isMe ? Colors.blue.shade300 : const Color.fromARGB(255, 230, 230, 230)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              bottomLeft: rightSide ? const Radius.circular(12) : const Radius.circular(1),
                              topRight: const Radius.circular(12),
                              bottomRight: rightSide ? const Radius.circular(1) : const Radius.circular(12))),
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: SelectableAutoLinkText(
                          text,
                          linkStyle: TextStyle(color: Colors.blue.shade800, decoration: TextDecoration.underline),
                          textAlign: TextAlign.start,
                          style: const TextStyle(fontSize: 22, color: Colors.black),
                          onTap: (link) => launchUrl(Uri.parse(link)),
                          onLongPress: (text) => SharePlus.instance.share(ShareParams(text: text)),
                        ),
                      ),
                    ),
                  ),
                  if (!isMe && rightSide) user,
                ]),
            Padding(
              padding: isMe ? const EdgeInsets.only(left: 12, right: 12) : const EdgeInsets.only(left: 50, right: 50),
              child: Row(
                mainAxisAlignment: rightSide ? MainAxisAlignment.end : MainAxisAlignment.start,
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
