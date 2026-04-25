import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<String?> enterPhoneNumberDialog(BuildContext context) async {
  final formKey = GlobalKey(debugLabel: "EnterPhoneNumberDialogFormKey");
  final numberKey = TextEditingController();
  return showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 80,
                  child: TextFormField(
                    autofocus: true,
                    controller: numberKey,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: "Phone Number"),
                  ),
                ),
              ),
              actions: [
                IconButton.filled(
                    onPressed: () {
                      return Navigator.pop(context, numberKey.text.trim());
                    },
                    icon: Icon(
                      Icons.check,
                      color: Colors.green,
                    ))
              ]));
}
