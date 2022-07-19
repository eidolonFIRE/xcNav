import 'dart:async';

import 'package:flutter/material.dart';

// --- Models
import 'package:xcnav/models/waypoint.dart';

// --- Widgets
import 'package:xcnav/widgets/map_marker.dart';

final TextEditingController newWaypointName = TextEditingController();

Future<Waypoint?>? editWaypoint(BuildContext context, final Waypoint waypoint,
    {VoidCallback? editPointsCallback, bool isPath = false, bool isNew = false}) {
  newWaypointName.value = TextEditingValue(text: waypoint.name);
  var formKey = GlobalKey<FormState>();

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
            iconOptions.forEach((key, value) => iconWidgets.add(IconButton(
                  onPressed: () => {setState(() => selectedIcon = key)},
                  padding: const EdgeInsets.all(0),
                  iconSize: 50,
                  color: selectedIcon == key ? selectedColor : Colors.grey,
                  icon: Container(
                    decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(Radius.circular(20)),
                        border: Border.all(
                            style: BorderStyle.solid,
                            width: 2,
                            color: (selectedIcon == key) ? Colors.white : Colors.transparent)),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        value,
                        size: 30,
                        color: (selectedIcon == key) ? Colors.white : Colors.grey,
                      ),
                    ),
                  ),
                )));
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
                Form(
                  key: formKey,
                  child: TextFormField(
                    controller: newWaypointName,
                    autofocus: true,
                    validator: (value) {
                      if (value != null) {
                        if (value.trim().isEmpty || value.isEmpty) return "Must not be empty";
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      hintText: "waypoint name",
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 20),
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
                const Divider(
                  height: 20,
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

                if (!showIconOptions && editPointsCallback != null)
                  TextButton.icon(
                      onPressed: () {
                        var newWaypoint = Waypoint(newWaypointName.text, waypoint.latlng, waypoint.isOptional,
                            selectedIcon, selectedColor.value);
                        Navigator.pop(context, newWaypoint);
                        editPointsCallback();
                      },
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.white,
                      ),
                      label: Text(
                        "Edit Path Points",
                        style: Theme.of(context).textTheme.button!.merge(const TextStyle(fontSize: 20)),
                      ))
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
                    if (formKey.currentState?.validate() ?? false) {
                      var newWaypoint = Waypoint(newWaypointName.text, waypoint.latlng, waypoint.isOptional,
                          selectedIcon, selectedColor.value);

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
