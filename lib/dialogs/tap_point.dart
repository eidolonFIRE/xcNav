import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/views/view_map.dart';

void tapPointDialog(
    BuildContext context, LatLng latlng, Function setFocusMode, void Function(Waypoint newWaypoint) onAddWaypoint) {
  final latlngString = "${latlng.latitude.toStringAsFixed(5)}, ${latlng.longitude.toStringAsFixed(5)}";
  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // --- latlng
          InkWell(
            onTap: () => {Share.share(latlngString)},
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Card(
                margin: EdgeInsets.zero,
                color: Colors.grey,
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: latlngString),
                      const WidgetSpan(
                        child: Padding(
                          padding: EdgeInsets.only(left: 10),
                          child: Icon(
                            Icons.copy,
                            color: Colors.black,
                          ),
                        ),
                      )
                    ]),
                    softWrap: false,
                    style: const TextStyle(fontSize: 18, color: Colors.black),
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // --- Add New Waypoint
                ElevatedButton.icon(
                    label: const Text("Waypoint"),
                    onPressed: () {
                      Navigator.pop(context);
                      editWaypoint(context, Waypoint(name: "", latlngs: [latlng]), isNew: true)?.then((newWaypoint) {
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
            ),
          )
        ]),
      );
    },
  );
}
