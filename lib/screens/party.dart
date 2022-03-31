import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

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

  showPartyActions(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              // title: Text("Group Actions"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Consumer<Group>(builder: (context, group, child) {
                    return (group.currentGroupID != null)
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text("Invite Code"),
                              Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(20)),
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: Container(
                                        // margin: const EdgeInsets.all(10),
                                        width: 300,
                                        height: 300,
                                        child: QrImage(
                                          foregroundColor: Colors.black,
                                          backgroundColor: Colors.white,
                                          data: group.currentGroupID!,
                                          version: QrVersions.auto,
                                          size: 300,
                                          gapless: true,
                                          padding: const EdgeInsets.all(30),
                                        )),
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                  onPressed: () =>
                                      {Share.share(group.currentGroupID ?? "")},
                                  icon: const Icon(Icons.share),
                                  label: Text(group.currentGroupID ?? "")),
                            ],
                          )
                        : const Padding(
                            padding: EdgeInsets.all(30.0),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          );
                  }),
                  ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, "/qrScanner");
                      },
                      icon: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.lightBlue,
                      ),
                      label: const Text("Scan Code")),
                  ElevatedButton.icon(
                      // TODO: prompt split option
                      onPressed: () {
                        Provider.of<Client>(context, listen: false)
                            .leaveGroup(false);
                        Navigator.popUntil(
                            context, ModalRoute.withName("/home"));
                      },
                      icon: const Icon(
                        Icons.logout,
                        color: Colors.red,
                      ),
                      label: const Text("Leave")),
                ]
                    .map((e) => Padding(
                          child: e,
                          padding: const EdgeInsets.all(5),
                        ))
                    .toList(),
              ),
            ));
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
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: IconButton(
                    iconSize: 35,
                    onPressed: () => {showPartyActions(context)},
                    icon: const Icon(Icons.groups)),
              ),
            ],
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
            chat.chatLastOpened = DateTime.now().millisecondsSinceEpoch;
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
                          20));
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
