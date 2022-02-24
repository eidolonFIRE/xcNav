import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';

// Providers
import 'package:xcnav/providers/client.dart';

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
                  Column(
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
                          data: 'This is a simple QR code',
                          version: QrVersions.auto,
                          size: 320,
                          gapless: true,
                        ),
                      ),
                      Text("<Invite URL here>"),
                    ],
                  ),
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
          title: Row(
            children: [
              IconButton(
                  onPressed: () => {showPartyActions(context)},
                  icon: Icon(Icons.groups)),
            ],
          ),
        ),
        body: Center(
          child: ListView.builder(itemBuilder: (context, i) {
            return Text("dummy");
          }),
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
