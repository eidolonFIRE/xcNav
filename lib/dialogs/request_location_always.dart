import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class RequestLocationDialog extends StatelessWidget {
  const RequestLocationDialog({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Text("${"Please enable:".tr()} location${Platform.isIOS ? "-always" : ""} ${"permission".tr()}."),
      actions: [
        ElevatedButton.icon(
          label: Text("Go to settings".tr()),
          icon: const Icon(Icons.open_in_new, color: Colors.lightGreen),
          onPressed: () {
            Navigator.pop(context);
            openAppSettings();
          },
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        )
      ],
    );
  }
}
