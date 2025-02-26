import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import 'package:share_plus/share_plus.dart';

// Providers
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';

class QRScanner extends StatefulWidget {
  const QRScanner({super.key});

  @override
  State<QRScanner> createState() => _QRScannerState();
}

class _QRScannerState extends State<QRScanner> {
  final TextEditingController inputGroupId = TextEditingController();
  final groupCodeExp = RegExp(r'^([0-9a-zA-Z]{6,})$');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // --- See current code
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Current Group",
                      style: TextStyle(fontSize: 22, color: Colors.grey),
                    ),
                    (Provider.of<Group>(context).currentGroupID == null)
                        ? const Center(
                            child: SizedBox(
                              width: 60,
                              height: 60,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : TextButton.icon(
                            iconAlignment: IconAlignment.end,
                            onPressed: () => {
                              Share.share(
                                  Provider.of<Group>(context, listen: false).currentGroupID?.toUpperCase() ?? "")
                            },
                            icon: const Icon(
                              Icons.share,
                              color: Colors.blue,
                            ),
                            label: Text(
                              Provider.of<Group>(context, listen: false).currentGroupID?.toUpperCase() ?? "",
                              style: TextStyle(fontSize: 32),
                            ),
                          ),
                  ],
                ),
              ),
            ),

            SizedBox(
              width: 200,
              height: 50,
              child: Container(),
            ),

            // --- Enter new code
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 50,
                  width: 200,
                  child: TextField(
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32),
                    textCapitalization: TextCapitalization.characters,
                    enableIMEPersonalizedLearning: false,
                    keyboardType: TextInputType.name,
                    decoration: const InputDecoration(hintText: "Join Code"),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9]"))],
                    controller: inputGroupId,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (text) => {handleCode(text)},
                  ),
                ),
                IconButton(
                    onPressed: () => {handleCode(inputGroupId.text)},
                    icon: const Icon(
                      Icons.login,
                      color: Colors.green,
                    ))
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool handleCode(String code) {
    if (groupCodeExp.hasMatch(code)) {
      debugPrint("Joined code: $code");

      Provider.of<Client>(context, listen: false).joinGroup(context, code);
      Navigator.pop(context);
      return true;
    } else {
      debugPrint("Invalid code: $code");
      return false;
    }
  }
}
