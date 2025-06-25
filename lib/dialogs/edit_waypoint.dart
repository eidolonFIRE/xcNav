import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// --- Models
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/widgets/latlng_editor.dart';

// --- Widgets
import 'package:xcnav/widgets/waypoint_marker.dart';

final TextEditingController newWaypointName = TextEditingController();

Future<Waypoint?>? editWaypoint(BuildContext context, final Waypoint waypoint,
    {bool isPath = false, bool isNew = false}) {
  newWaypointName.value = TextEditingValue(text: waypoint.name);
  var formKey = GlobalKey<FormState>();
  List<LatLng> tempLatlngs = waypoint.latlng.toList();
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
              "${isNew ? "btn.Add".tr() : "btn.Edit".tr()} ${isPath ? "Path".tr() : "Waypoint".tr()}",
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
                          if (value.trim().isEmpty || value.isEmpty) return "warning_empty".tr();
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: "${isPath ? "Path".tr() : "Waypoint".tr()} ${"Name".tr()}",
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
                        color: Theme.of(context).colorScheme.surface,
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
                      child: LatLngEditor(
                        initialLatlngs: waypoint.latlng,
                        onLatLngs: (latlngs) {
                          tempLatlngs = latlngs;
                        },
                      )),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceAround,
            actions: [
              ElevatedButton.icon(
                  label: Text("btn.Cancel".tr()),
                  onPressed: () => {Navigator.pop(context)},
                  icon: const Icon(
                    Icons.cancel,
                    size: 20,
                    color: Colors.red,
                  )),
              ElevatedButton.icon(
                  label: Text(isNew ? "btn.Add".tr() : "btn.Update".tr()),
                  onPressed: () {
                    if ((formKey.currentState?.validate() ?? false) && (tempLatlngs.isNotEmpty)) {
                      var newWaypoint = Waypoint(
                          newId: waypoint.id,
                          name: newWaypointName.text,
                          latlngs: tempLatlngs,
                          icon: selectedIcon,
                          color: selectedColor.toARGB32());

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
