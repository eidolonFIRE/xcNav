import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/models/flight_plan.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/plans.dart';

/// Returns bool didSave?
Future<bool?> savePlan(BuildContext context, {bool isSavingFirst = false}) {
  var formKey = GlobalKey<FormState>();
  ActivePlan activePlan = Provider.of<ActivePlan>(context, listen: false);
  TextEditingController filename = TextEditingController();

  // No need if plan is empty or if the plan is unchanged
  if (activePlan.waypoints.isEmpty || isSavingFirst && activePlan.isSaved) {
    return Future.value(false);
  }

  void onDone(BuildContext context) {
    final newPlan = FlightPlan.fromActivePlan(filename.text, activePlan);
    activePlan.isSaved = true;
    Provider.of<Plans>(context, listen: false).setPlan(newPlan).then((_) => Navigator.pop(context, true));
  }

  return showDialog<bool?>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("Save Waypoints to Library${isSavingFirst ? " before they are replaced?" : ""}"),
      content: Form(
        key: formKey,
        child: TextFormField(
          textInputAction: TextInputAction.done,
          controller: filename,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "collection name",
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 20),
          validator: (value) {
            if (value != null) {
              if (value.trim().isEmpty) return "Must not be empty";
              if (Provider.of<Plans>(context, listen: false).hasPlan(value)) {
                return "Name already in use";
              }
            }
            return null;
          },
          onEditingComplete: () => onDone(context),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceAround,
      actions: [
        ElevatedButton.icon(
            label: Text(isSavingFirst ? "No" : "Cancel"),
            onPressed: () => {Navigator.pop(context, false)},
            icon: const Icon(
              Icons.cancel,
              size: 20,
              color: Colors.red,
            )),
        ElevatedButton.icon(
            label: const Text("Save"),
            onPressed: () => onDone(context),
            icon: const Icon(
              Icons.save,
              size: 20,
              color: Colors.lightGreen,
            )),
      ],
    ),
  );
}
