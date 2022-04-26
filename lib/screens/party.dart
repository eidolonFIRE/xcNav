import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/chat.dart';
import 'package:xcnav/providers/profile.dart';

// Models
import 'package:xcnav/models/message.dart';
import 'package:xcnav/models/pilot.dart';

// Widgets
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/chat_bubble.dart';

class Party extends StatefulWidget {
  const Party({Key? key}) : super(key: key);

  @override
  State<Party> createState() => _PartyState();
}

class _PartyState extends State<Party> {
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
      Provider.of<Client>(context, listen: false)
          .sendchatMessage(text, isEmergency: false);
      chatInput.clear();

      Provider.of<Chat>(context, listen: false).processSentMessage(
          DateTime.now().millisecondsSinceEpoch,
          Provider.of<Profile>(context, listen: false).id ?? "",
          text,
          false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
            // actions: [
            //   IconButton(
            //       iconSize: 30,
            //       onPressed: () => {Navigator.pushNamed(context, "/qrScanner")},
            //       icon: const Icon(
            //         Icons.qr_code_scanner,
            //         color: Colors.lightBlue,
            //       ))
            // ],
            title: Consumer<Group>(
                builder: (context, group, child) => Row(
                      children: group.pilots.values
                          .toList()
                          .map((e) => AvatarRound(e.avatar, 20))
                          .toList(),
                    ))),
        // --- Chat Bubble List
        body: Center(
          child: Consumer<Chat>(builder: (context, chat, child) {
            // TODO: this isn't super reliable
            chat.chatLastOpened = DateTime.now().millisecondsSinceEpoch;
            chat.numUnread = 0;
            return ListView.builder(
                itemCount: chat.messages.length,
                reverse: true,
                itemBuilder: (context, i) {
                  final reversedIndex = chat.messages.length - 1 - i;
                  Message msg = chat.messages[reversedIndex];
                  Pilot? pilot = Provider.of<Group>(context, listen: false)
                      .pilots[msg.pilotId];
                  return ChatBubble(
                    msg.pilotId ==
                        Provider.of<Profile>(context, listen: false).id,
                    msg.text,
                    AvatarRound(
                        pilot?.avatar ??
                            Image.asset("assets/images/default_avatar.png"),
                        20),
                    Provider.of<Group>(context, listen: false)
                        .pilots[msg.pilotId]
                        ?.name,
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
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(10)),
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
                  side: MaterialStateProperty.resolveWith<BorderSide>(
                      (states) => const BorderSide(color: Colors.blue)),
                  backgroundColor: MaterialStateProperty.resolveWith<Color>(
                      (states) => Colors.blue),
                ),
                child: const Icon(Icons.send)),
          ],
        ),
      ),
    );
  }
}
