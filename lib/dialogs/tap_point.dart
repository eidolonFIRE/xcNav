import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/views/view_map.dart';

void tapPointDialog(BuildContext context, LatLng latlng, Function setFocusMode) {
  const unitStyle = TextStyle(fontSize: 20, color: Colors.grey);
  final latlngString = "${latlng.latitude.toStringAsFixed(5)}, ${latlng.longitude.toStringAsFixed(5)}";
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          // --- latlng
          InkWell(
            onTap: () => {Share.share(latlngString)},
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

          // --- elevation

          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: FutureBuilder<double?>(
              initialData: 0,
              future: sampleDem(latlng),
              builder: (context, snapshot) {
                return Text.rich(TextSpan(children: [
                  const TextSpan(text: "Ground Height:     ", style: unitStyle),
                  richValue(UnitType.distFine, snapshot.data ?? 0,
                      digits: 5, valueStyle: const TextStyle(fontSize: 45), unitStyle: unitStyle)
                ]));
              },
            ),
          )
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          // --- Add New Waypoint
          ElevatedButton.icon(
              label: const Text("Waypoint"),
              onPressed: () {
                var plan = Provider.of<ActivePlan>(context, listen: false);
                Navigator.pop(context);
                editWaypoint(context, Waypoint("", [latlng], null, null), isNew: true)?.then((newWaypoint) {
                  if (newWaypoint != null) {
                    plan.insertWaypoint(plan.waypoints.length, newWaypoint.name, newWaypoint.latlng, false,
                        newWaypoint.icon, newWaypoint.color);
                  }
                });
              },
              icon: const ImageIcon(
                AssetImage("assets/images/add_waypoint_pin.png"),
                color: Colors.lightGreen,
              )),
          // --- Add New Path
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: ElevatedButton.icon(
                label: const Text("Path"),
                onPressed: () {
                  Navigator.pop(context);
                  setFocusMode(FocusMode.addPath);
                },
                icon: const ImageIcon(
                  AssetImage("assets/images/add_waypoint_path.png"),
                  color: Colors.yellow,
                )),
          ),
        ],
      );
    },
  );
}
