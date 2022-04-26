import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

// --- Models
import 'package:xcnav/models/waypoint.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';

// --- Widgets
import 'package:xcnav/widgets/map_marker.dart';

final TextEditingController newWaypointName = TextEditingController();

void editWaypoint(BuildContext context, bool isNew, List<LatLng> latlngs,
    {VoidCallback? editPointsCallback}) {
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
      builder: (context) {
        Color? selectedColor =
            isNew ? null : Color(currentWp?.color ?? Colors.black.value);
        String? selectedIcon = isNew ? null : currentWp?.icon;

        bool showIconOptions = isNew
            ? (latlngs.length == 1)
            : (currentWp != null ? currentWp.latlng.length <= 1 : true);

        return StatefulBuilder(builder: (context, setState) {
          // --- Build color selection buttons
          List<Widget> colorWidgets = [];
          colorOptions.forEach((key, value) => colorWidgets.add(Expanded(
                // width: 40,

                child: MaterialButton(
                  onPressed: () => {setState(() => selectedColor = value)},
                  height: value == selectedColor ? 60 : 40,
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
                        borderRadius:
                            const BorderRadius.all(Radius.circular(20)),
                        border: Border.all(
                            style: BorderStyle.solid,
                            width: 2,
                            color: (selectedIcon == key)
                                ? Colors.white
                                : Colors.transparent)),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        value,
                        size: 30,
                        color:
                            (selectedIcon == key) ? Colors.white : Colors.grey,
                      ),
                    ),
                  ),
                )));
          }
          return AlertDialog(
            title: Text(
              isNew ? "Add Waypoint" : "Edit Waypoint",
              style: Theme.of(context).textTheme.titleSmall,
            ),
            titlePadding: const EdgeInsets.all(10),
            contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Edit Name
                TextField(
                  controller: newWaypointName,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: "waypoint name",
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 20),
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
                        color: Colors.grey[900],
                        child: GridView.count(
                          crossAxisCount: 5,
                          children: iconWidgets,
                        ),
                      ),
                    ),
                  ),

                if (!showIconOptions)
                  TextButton.icon(
                      onPressed: editPointsCallback ?? (() => {}),
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.white,
                      ),
                      label: Text(
                        "Edit Path Points",
                        style: Theme.of(context)
                            .textTheme
                            .button!
                            .merge(const TextStyle(fontSize: 20)),
                      ))
              ],
            ),
            actions: [
              ElevatedButton.icon(
                  label: Text(isNew ? "Add" : "Update"),
                  onPressed: () {
                    if (newWaypointName.text.isNotEmpty) {
                      if (isNew) {
                        // --- Make new waypoint
                        Provider.of<ActivePlan>(context, listen: false)
                            .insertWaypoint(null, newWaypointName.text, latlngs,
                                false, selectedIcon, selectedColor?.value);
                      } else {
                        // --- Update selected waypoint
                        Provider.of<ActivePlan>(context, listen: false)
                            .updateWaypoint(null, newWaypointName.text,
                                selectedIcon, selectedColor?.value, latlngs);
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
          );
        });
      });
}
