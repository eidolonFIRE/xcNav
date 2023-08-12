import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:xcnav/units.dart';

Future<bool?> confirmLogTrim(BuildContext context,
    {required String cutLabel,
    required DateTime newTime,
    required int sampleCount,
    required Duration trimLength}) async {
  return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text.rich(TextSpan(children: [
              TextSpan(
                text: "Trim $cutLabel?",
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
              TextSpan(text: "New $cutLabel:   "),
              TextSpan(
                  text: intl.DateFormat("h:mm a").format(newTime), style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: "\n"),
              const TextSpan(text: "Removing:   "),
              TextSpan(text: "$sampleCount", style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: " samples, which is  "),
              richMinSec(valueStyle: const TextStyle(fontWeight: FontWeight.bold), duration: trimLength),
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
