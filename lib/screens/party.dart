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
                              Text("Invite Code"),
                              SizedBox(
                                  width: 300,
                                  height: 300,
                                  child: QrImage(
                                    foregroundColor: Colors.white,
                                    backgroundColor: Colors.black,
                                    // TODO: get group ID invite code
                                    data: group.currentGroupID!,
                                    version: QrVersions.auto,
                                    size: 320,
                                    gapless: true,
                                  )),
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
                        // Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
            actions: [
              IconButton(
                  onPressed: () => {showPartyActions(context)},
                  icon: const Icon(Icons.groups)),
            ],
            title: Consumer<Group>(
                builder: (context, group, child) => Row(
                      children: group.pilots.values
                          .toList()
                          .map((e) => AvatarRound(e.avatar, 10))
                          .toList(),
                    ))),
        body: Center(
          child: Consumer<Chat>(
            builder: (context, chat, child) => ListView.builder(
                itemCount: chat.messages.length,
                itemBuilder: (context, i) {
                  Message msg = chat.messages[i];
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
                }),
          ),
        ),
        bottomNavigationBar: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: TextField(
                textInputAction: TextInputAction.send,
                controller: chatInput,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  debugPrint("send: $value");
                  chatInput.clear();
                },
              ),
            ),
            ElevatedButton(onPressed: () => {}, child: const Icon(Icons.send)),
          ],
        ),
      ),
    );
  }
}
