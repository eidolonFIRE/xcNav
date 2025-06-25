import 'package:easy_localization/easy_localization.dart';
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
            title: Text(
                "${((prevName != null && prevName.isNotEmpty) ? "btn.Rename".tr() : "btn.New".tr())} ${"Collection".tr()}"),
            actions: [
              TextButton.icon(
                  label: Text("btn.Cancel".tr()),
                  onPressed: () => {Navigator.pop(context, null)},
                  icon: const Icon(
                    Icons.cancel,
                    size: 20,
                    color: Colors.red,
                  )),
              TextButton.icon(
                  label: Text("btn.Ok".tr()),
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
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z0-9_ -()\.]"))],
                  validator: (value) {
                    if (value != null) {
                      if (value.trim().isEmpty) return "warning_empty".tr();
                      if (Provider.of<Plans>(context, listen: false).hasPlan(value)) return "warning_name_in_use".tr();
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: "Name".tr(),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 20),
                  onEditingComplete: onDone),
            ));
      });
}
