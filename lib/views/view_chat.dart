import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/profile.dart';

// Models
import 'package:xcnav/models/message.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/providers/settings.dart';

// Widgets
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/chat_bubble.dart';

const List<String> quickchat = [
  "Waiting here... ⏱️",
  "Let's Gooooo!",
  "Where to? 🤷",
  "Turning back ↩️",
  "Landed ok 🛬",
  "",
  "Good Air 🧈",
  "Hazardous ☠️",
  "",
  "Emergency: Engine out!",
  "Low fuel ⚠️",
  "Ignore last",
  // "Emergency: Landing immediately!",
];

class ViewChat extends StatefulWidget {
  const ViewChat({Key? key}) : super(key: key);

  @override
  State<ViewChat> createState() => ViewChatState();
}

class ViewChatState extends State<ViewChat> {
  final TextEditingController chatInput = TextEditingController();

  FocusNode? inputFieldNode;

  @override
  void initState() {
    inputFieldNode = FocusNode();
    super.initState();
  }

  @override
  void dispose() {
    inputFieldNode?.dispose();
    super.dispose();
  }

  void sendChatMessage(String text) {
    if (text.trim() != "") {
      Provider.of<Client>(context, listen: false).sendchatMessage(text, isEmergency: false);
      chatInput.clear();

      Provider.of<ChatMessages>(context, listen: false).processSentMessage(
          DateTime.now().millisecondsSinceEpoch, Provider.of<Profile>(context, listen: false).id ?? "", text, false);
    }
  }

  void showQuickMessageMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
            alignment: Alignment.topCenter,
            children: quickchat
                .map((msg) => (msg == "")
                    ? const Divider(
                        thickness: 2,
                        height: 10,
                      )
                    : SimpleDialogOption(
                        child: Text(
                          msg.startsWith("Emergency:") ? msg.substring(11) : msg,
                          style: Theme.of(context)
                              .textTheme
                              .headline6!
                              .merge(TextStyle(color: msg.startsWith("Emergency:") ? Colors.red : Colors.white)),
                        ),
                        onPressed: () => Navigator.pop(context, msg),
                      ))
                .toList());
      },
    ).then((value) => {if (value != null) sendChatMessage(value)});
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("Build /home/view_chat");
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(children: [
        // --- Chat Bubble List
        Expanded(
          child: Stack(
            children: [
              Consumer<ChatMessages>(builder: (context, chat, child) {
                Provider.of<ChatMessages>(context, listen: false).markAllRead(false);
                return ListView.builder(
                    itemCount: chat.messages.length,
                    reverse: true,
                    itemBuilder: (context, i) {
                      final reversedIndex = chat.messages.length - 1 - i;
                      Message msg = chat.messages[reversedIndex];
                      Pilot? pilot = Provider.of<Group>(context, listen: false).pilots[msg.pilotId];
                      return ChatBubble(
                        msg.pilotId == Provider.of<Profile>(context, listen: false).id,
                        msg.text,
                        AvatarRound(pilot?.avatar ?? Image.asset("assets/images/default_avatar.png"), 20),
                        Provider.of<Group>(context, listen: false).pilots[msg.pilotId]?.name,
                        msg.timestamp,
                      );
                    });
              }),

              // --- Text to Speak toggle
              Consumer<Settings>(
                  builder: (context, settings, child) => Positioned(
                        left: 8,
                        top: 8,
                        child: FloatingActionButton(
                          backgroundColor:
                              settings.chatTts ? Colors.greenAccent.withAlpha(200) : Colors.red.shade900.withAlpha(100),
                          child: Icon(
                            settings.chatTts ? Icons.volume_up : Icons.volume_off,
                            color: Colors.black,
                            size: 30,
                          ),
                          onPressed: () => settings.chatTts = !settings.chatTts,
                        ),
                      )),

              // --- Group Menu
              Positioned(
                  right: 8,
                  top: 8,
                  child: FloatingActionButton(
                      backgroundColor: Colors.grey,
                      heroTag: "group",
                      onPressed: (() {
                        Navigator.pushNamed(context, "/groupDetails");
                      }),
                      child: const Icon(
                        Icons.group_add,
                        size: 30,
                      )))
            ],
          ),
        ),
        // --- Text Input
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            /// Quick messages
            IconButton(icon: const Icon(Icons.bolt), onPressed: () => {showQuickMessageMenu(context)}),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: TextField(
                  style: const TextStyle(fontSize: 20),
                  textInputAction: TextInputAction.send,
                  controller: chatInput,
                  autofocus: true,
                  focusNode: inputFieldNode,
                  decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      contentPadding: const EdgeInsets.all(8)),
                  onSubmitted: (value) {
                    sendChatMessage(value);
                    if (inputFieldNode != null) {
                      FocusScope.of(context).requestFocus(inputFieldNode);
                    }
                  },
                ),
              ),
            ),
            ElevatedButton(
                onPressed: () => {sendChatMessage(chatInput.text)},
                style: ButtonStyle(
                  side: MaterialStateProperty.resolveWith<BorderSide>((states) => const BorderSide(color: Colors.blue)),
                  backgroundColor: MaterialStateProperty.resolveWith<Color>((states) => Colors.blue),
                ),
                child: const Icon(Icons.send)),
          ],
        ),
      ]),
    );
  }
}
