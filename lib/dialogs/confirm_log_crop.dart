import 'package:flutter/material.dart';
import 'package:xcnav/units.dart';

Future<bool?> confirmLogCrop(BuildContext context, {required Duration trimStart, required Duration trimEnd}) async {
  return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text.rich(TextSpan(children: [
              TextSpan(
                text: "Trim log to selection?",
                style: const TextStyle(color: Colors.amber),
              ),
              WidgetSpan(
                  child: Container(
                width: 20,
              )),
              const TextSpan(
                text: "No Undo!",
                style: TextStyle(color: Colors.red),
              ),
            ])),
            content: Text.rich(TextSpan(children: [
              const TextSpan(text: "Removing:   "),
              richMinSec(valueStyle: const TextStyle(fontWeight: FontWeight.bold), duration: trimStart),
              const TextSpan(text: " from start, and "),
              richMinSec(valueStyle: const TextStyle(fontWeight: FontWeight.bold), duration: trimEnd),
              const TextSpan(text: " from the end."),
            ])),
            actions: [
              ElevatedButton.icon(
                  icon: const Icon(
                    Icons.cancel,
                    color: Colors.red,
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  label: const Text("Cancel")),
              ElevatedButton.icon(
                  icon: const Icon(
                    Icons.check,
                    color: Colors.lightGreen,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  label: const Text("Yes"))
            ],
          ));
}
