import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class RequestLocationAlways extends StatelessWidget {
  const RequestLocationAlways({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Platform.isIOS
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text("Please set location permission to \"always\"."),
                Text(" - Required to access location while screen is off."),
                Text(" - Can only get location while app is active.")
              ],
            )
          : const Text("Please enable location permission."),
      actions: [
        IconButton(
          icon: const Icon(Icons.launch, color: Colors.lightGreen),
          onPressed: () {
            Navigator.pop(context);
            openAppSettings();
          },
        )
      ],
    );
  }
}
