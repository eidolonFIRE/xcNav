import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class RequestLocationDialog extends StatelessWidget {
  const RequestLocationDialog({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Text("Please enable location${Platform.isIOS ? "-always" : ""} permission."),
      actions: [
        ElevatedButton.icon(
          label: Text("Go to settings"),
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
