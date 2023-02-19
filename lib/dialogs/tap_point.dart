import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/views/view_map.dart';
import 'package:xcnav/widgets/latlng_editor.dart';

void tapPointDialog(
    BuildContext context, LatLng latlng, Function setFocusMode, void Function(Waypoint newWaypoint) onAddWaypoint) {
  var latlngs = [latlng];
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        content:
            // --- latlng
            LatLngEditor(
          initialLatlngs: latlngs,
          onLatLngs: ((newLatlngs) {
            latlngs = newLatlngs;
          }),
        ),
        actions: [
          // --- Add New Waypoint
          ElevatedButton.icon(
              label: const Text("Waypoint"),
              onPressed: () {
                Navigator.pop(context);
                editWaypoint(context, Waypoint(name: "", latlngs: latlngs), isNew: true)?.then((newWaypoint) {
                  if (newWaypoint != null) {
                    onAddWaypoint(newWaypoint);
                  }
                });
              },
              icon: const ImageIcon(
                AssetImage("assets/images/add_waypoint_pin.png"),
                color: Colors.lightGreen,
              )),
          // --- Add New Path
          ElevatedButton.icon(
              label: const Text("Path"),
              onPressed: () {
                Navigator.pop(context);
                setFocusMode(FocusMode.addPath);
              },
              icon: const ImageIcon(
                AssetImage("assets/images/add_waypoint_path.png"),
                color: Colors.yellow,
              )),
        ],
      );
    },
  );
}
