import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

// --- Models
import 'package:xcnav/models/waypoint.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';

final TextEditingController filename = TextEditingController();

void savePlan(BuildContext context) {
  ActivePlan plan = Provider.of<ActivePlan>(context, listen: false);

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Save New Plan"),
      content: TextField(
        controller: filename,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: "plan name",
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 20),
      ),
      actions: [
        ElevatedButton.icon(
            label: Text("Save"),
            onPressed: () {
              // TODO: Save plan to file

              getApplicationDocumentsDirectory().then((tempDir) {
                File logFile =
                    File("${tempDir.path}/flight_plans/${filename.text}.json");

                logFile
                    .create(recursive: true)
                    .then((value) => logFile.writeAsString(jsonEncode({
                          "title": filename.text,
                          "waypoints":
                              plan.waypoints.map((e) => e.toJson()).toList()
                        })));
              });
              Navigator.pop(context);
            },
            icon: const Icon(
              Icons.save,
              size: 20,
              color: Colors.lightGreen,
            )),
        ElevatedButton.icon(
            label: const Text("Cancel"),
            onPressed: () => {Navigator.pop(context)},
            icon: const Icon(
              Icons.cancel,
              size: 20,
              color: Colors.red,
            )),
      ],
    ),
  );
}
