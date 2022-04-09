import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

// --- Models
import 'package:xcnav/models/waypoint.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';

final TextEditingController newWaypointName = TextEditingController();

void editWaypoint(BuildContext context, bool isNew, LatLng? latlng) {
  Waypoint? currentWp =
      Provider.of<ActivePlan>(context, listen: false).selectedWp;
  if (!isNew) {
    if (currentWp != null) {
      // --- Load in currently selected waypoint options
      newWaypointName.value = TextEditingValue(text: currentWp.name);
    } else {
      // no waypoint selected to edit!
      return;
    }
  }
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Add Waypoint"),
      content: TextField(
        controller: newWaypointName,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: "waypoint name",
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 20),
      ),
      actions: [
        ElevatedButton.icon(
            label: Text(isNew ? "Add" : "Update"),
            onPressed: () {
              // TODO: marker icon and color options
              if (newWaypointName.text.isNotEmpty) {
                if (isNew) {
                  // --- Make new waypoint
                  Provider.of<ActivePlan>(context, listen: false)
                      .insertWaypoint(null, newWaypointName.text, latlng!,
                          false, null, null);
                } else {
                  // --- Update selected waypoint
                  // TODO: set icon and color
                  Provider.of<ActivePlan>(context, listen: false)
                      .editWaypoint(null, newWaypointName.text, null, null);
                }
                Navigator.pop(context);
              }
            },
            icon: const Icon(
              Icons.check,
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
