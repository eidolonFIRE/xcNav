import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class RequestLocationDialog extends StatelessWidget {
  const RequestLocationDialog({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: const Text("Please enable location permission."),
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
