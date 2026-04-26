import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

Future<String?> showRenameDialog(BuildContext context, {String? text}) {
  final TextEditingController name = TextEditingController(text: text);
  return showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            "btn.Rename".tr(),
          ),
          content: TextFormField(
            autofocus: true,
            controller: name,
          ),
          actions: [
            ElevatedButton.icon(
                label: Text("btn.Save".tr()),
                onPressed: () {
                  Navigator.pop(context, name.text);
                },
                icon: const Icon(
                  Icons.check,
                  color: Colors.green,
                )),
          ],
        );
      });
}
