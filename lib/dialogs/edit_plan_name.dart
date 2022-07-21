import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/providers/plans.dart';

Future<String?> editPlanName(BuildContext context, String? prevName) {
  var formKey = GlobalKey<FormState>();
  var textController = TextEditingController();
  if (prevName != null) textController.text = prevName;

  void onDone() {
    if (formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, textController.text.trim());
    }
  }

  return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
            title: Text(((prevName != null && prevName.isNotEmpty) ? "Rename" : "New") + " Plan / Collection"),
            actions: [
              TextButton.icon(
                  label: const Text("Cancel"),
                  onPressed: () => {Navigator.pop(context, null)},
                  icon: const Icon(
                    Icons.cancel,
                    size: 20,
                    color: Colors.red,
                  )),
              TextButton.icon(
                  label: const Text("Ok"),
                  onPressed: onDone,
                  icon: const Icon(
                    Icons.check,
                    size: 20,
                    color: Colors.lightGreen,
                  )),
            ],
            content: Form(
              key: formKey,
              child: TextFormField(
                  textInputAction: TextInputAction.done,
                  controller: textController,
                  autofocus: true,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9_ -()]"))],
                  validator: (value) {
                    if (value != null) {
                      if (value.trim().isEmpty) return "Must not be empty";
                      if (Provider.of<Plans>(context, listen: false).hasPlan(value)) return "Name already in use";
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    hintText: "Name",
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 20),
                  onEditingComplete: onDone),
            ));
      });
}
