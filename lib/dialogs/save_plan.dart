import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/models/flight_plan.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';

final TextEditingController filename = TextEditingController();

Future<bool?> savePlan(BuildContext context, {bool isSavingFirst = false}) {
  ActivePlan plan = Provider.of<ActivePlan>(context, listen: false);

  return showDialog<bool?>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("Save Active Plan" + (isSavingFirst ? " before it is replaced?" : "")),
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
            label: const Text("Save"),
            onPressed: () {
              FlightPlan.fromActivePlan(plan, filename.text).saveToFile().then((_) => Navigator.pop(context, true));
            },
            icon: const Icon(
              Icons.save,
              size: 20,
              color: Colors.lightGreen,
            )),
        ElevatedButton.icon(
            label: Text(isSavingFirst ? "No" : "Cancel"),
            onPressed: () => {Navigator.pop(context, false)},
            icon: const Icon(
              Icons.cancel,
              size: 20,
              color: Colors.red,
            )),
      ],
    ),
  );
}
