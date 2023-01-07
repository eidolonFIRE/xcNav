import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// --- Models
import 'package:xcnav/models/waypoint.dart';

// --- Widgets
import 'package:xcnav/widgets/map_marker.dart';

final TextEditingController newWaypointName = TextEditingController();

Future<Waypoint?>? editWaypoint(BuildContext context, final Waypoint waypoint,
    {bool isPath = false, bool isNew = false}) {
  newWaypointName.value = TextEditingValue(text: waypoint.name);
  var formKey = GlobalKey<FormState>();
  var formKeyLatlng = GlobalKey<FormState>();
  final reMatch = RegExp(r"([-\d]+.?[\d]*),[\s]*([-\d]+.?[\d]*)");
  final TextEditingController latlngText = TextEditingController(
      text:
          waypoint.latlng.map((e) => "${e.latitude.toStringAsFixed(5)}, ${e.longitude.toStringAsFixed(5)}").join("; "));
  debugPrint(
      waypoint.latlng.map((e) => "${e.latitude.toStringAsFixed(5)}, ${e.longitude.toStringAsFixed(5)}").join("; "));
  return showDialog<Waypoint?>(
      context: context,
      builder: (context) {
        Color selectedColor = waypoint.getColor();
        String? selectedIcon = waypoint.icon;

        bool showIconOptions = waypoint.latlng.length < 2 && !isPath;

        return StatefulBuilder(builder: (context, setState) {
          // --- Build color selection buttons
          List<Widget> colorWidgets = [];
          colorOptions.forEach((key, value) => colorWidgets.add(Expanded(
                // width: 40,

                child: MaterialButton(
                  onPressed: () => {setState(() => selectedColor = value)},
                  height: value == selectedColor ? 50 : 30,
                  color: value,
                  // child: Container(),
                ),
              )));

          // --- Build icon selection buttons
          List<Widget> iconWidgets = [];
          if (showIconOptions) {
            for (final name in iconOptions.keys) {
              iconWidgets.add(IconButton(
                onPressed: () => {setState(() => selectedIcon = name)},
                padding: const EdgeInsets.all(0),
                iconSize: 50,
                color: selectedIcon == name ? selectedColor : Colors.grey,
                icon: Container(
                  decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.circular(20)),
                      border: Border.all(
                          style: BorderStyle.solid,
                          width: 2,
                          color: (selectedIcon == name) ? Colors.white : Colors.transparent)),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: getWpIcon(
                      name,
                      30,
                      (selectedIcon == name) ? Colors.white : Colors.grey,
                    ),
                  ),
                ),
              ));
            }
          }

          return AlertDialog(
            title: Text(
              (isNew ? "Add " : "Edit ") + (isPath ? "Path" : "Waypoint"),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            titlePadding: const EdgeInsets.all(10),
            contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Edit Name
                SizedBox(
                  height: 50,
                  child: Form(
                    key: formKey,
                    child: TextFormField(
                      key: const Key("editWaypointName"),
                      controller: newWaypointName,
                      autofocus: true,
                      validator: (value) {
                        if (value != null) {
                          if (value.trim().isEmpty || value.isEmpty) return "Must not be empty";
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: "${isPath ? "Path" : "Waypoint"} Name",
                        border: const OutlineInputBorder(),
                      ),
                      textAlignVertical: TextAlignVertical.bottom,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                const Divider(
                  height: 20,
                ),
                // --- Edit Color
                Flex(
                  direction: Axis.horizontal,
                  children: colorWidgets,
                ),

                // --- Edit Icon
                if (showIconOptions)
                  Expanded(
                    child: SizedBox(
                      width: double.maxFinite,
                      child: Card(
                        color: Theme.of(context).backgroundColor,
                        child: GridView.count(
                          crossAxisCount: 5,
                          children: iconWidgets,
                        ),
                      ),
                    ),
                  ),

                const Divider(
                  height: 20,
                ),

                // --- Edit LatLng
                Padding(
                  padding: const EdgeInsets.only(left: 30, right: 30),
                  child: SizedBox(
                    height: 50,
                    child: Form(
                      key: formKeyLatlng,
                      child: TextFormField(
                        maxLines: 1,

                        controller: latlngText,
                        // autofocus: true,
                        validator: (value) {
                          if (value != null) {
                            if (value.trim().isEmpty) return "Must not be empty";
                            if (!reMatch.hasMatch(value)) return "Unrecognized Format";
                          }
                          return null;
                        },
                        decoration: const InputDecoration(
                          hintText: "Lat, Long  (or google-maps url)",
                          // border: OutlineInputBorder(),
                        ),
                        textAlign: TextAlign.center,
                        textAlignVertical: TextAlignVertical.bottom,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                  label: const Text("Cancel"),
                  onPressed: () => {Navigator.pop(context)},
                  icon: const Icon(
                    Icons.cancel,
                    size: 20,
                    color: Colors.red,
                  )),
              TextButton.icon(
                  label: Text(isNew ? "Add" : "Update"),
                  onPressed: () {
                    if ((formKey.currentState?.validate() ?? false) &&
                        (formKeyLatlng.currentState?.validate() ?? false)) {
                      final latLngValues = reMatch.allMatches(latlngText.text);

                      var newWaypoint = Waypoint(
                          newId: waypoint.id,
                          name: newWaypointName.text,
                          latlngs: latLngValues.isEmpty
                              ? waypoint.latlng
                              : latLngValues
                                  .map((e) => LatLng(double.parse(e.group(1)!), double.parse(e.group(2)!)))
                                  .toList(),
                          icon: selectedIcon,
                          color: selectedColor.value);

                      Navigator.pop(context, newWaypoint);
                    }
                  },
                  icon: const Icon(
                    Icons.check,
                    size: 20,
                    color: Colors.lightGreen,
                  )),
            ],
          );
        });
      });
}
