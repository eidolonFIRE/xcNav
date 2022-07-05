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

class Chat extends StatefulWidget {
  const Chat({Key? key}) : super(key: key);

  @override
  State<Chat> createState() => _ChatState();
}

class _ChatState extends State<Chat> {
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

  @override
  Widget build(BuildContext context) {
    Provider.of<ChatMessages>(context, listen: false).markAllRead(false);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Provider.of<ChatMessages>(context, listen: false).markAllRead(true);
              Navigator.of(context).pop();
            },
          ),
          title: IconButton(
              icon: const Icon(Icons.auto_awesome),
              onPressed: () => {
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
                                          style: Theme.of(context).textTheme.headline6!.merge(TextStyle(
                                              color: msg.startsWith("Emergency:") ? Colors.red : Colors.white)),
                                        ),
                                        onPressed: () => Navigator.pop(context, msg),
                                      ))
                                .toList());
                      },
                    ).then((value) => {if (value != null) sendChatMessage(value)})
                  }),
        ),
        // --- Chat Bubble List
        body: Center(
          child: Consumer<ChatMessages>(builder: (context, chat, child) {
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
        ),
        // --- Text Input
        bottomNavigationBar: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: TextField(
                  textInputAction: TextInputAction.send,
                  controller: chatInput,
                  autofocus: true,
                  focusNode: inputFieldNode,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
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
      ),
    );
  }
}
