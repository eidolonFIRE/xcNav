import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

// --- Dialogs
import 'package:xcnav/dialogs/save_plan.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/plans.dart';

// --- Widgets
import 'package:xcnav/widgets/waypoint_card.dart';

// --- Misc
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/screens/home.dart';

// --- Models
import 'package:xcnav/models/waypoint.dart';

class ViewWaypoints extends StatefulWidget {
  const ViewWaypoints({Key? key}) : super(key: key);

  @override
  State<ViewWaypoints> createState() => ViewWaypointsState();
}

class ViewWaypointsState extends State<ViewWaypoints> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ActivePlan>(builder: (context, activePlan, child) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Waypoint menu buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(onPressed: () => {Navigator.pushNamed(context, "/plans")}, icon: const Icon(Icons.bookmarks)),

              // --- Save Plan
              PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case "save":
                        Navigator.pop(context);
                        savePlan(context);
                        break;
                      case "clear":
                        showDialog(
                            context: context,
                            builder: (BuildContext ctx) {
                              return AlertDialog(
                                title: const Text('Are you sure?'),
                                content: const Text('This will clear the flight plan for everyone in the group!'),
                                actions: [
                                  TextButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).pop(true);
                                      },
                                      icon: const Icon(
                                        Icons.delete_forever,
                                        color: Colors.red,
                                      ),
                                      label: const Text('Clear')),
                                  TextButton(
                                      onPressed: () {
                                        // Close the dialog
                                        Navigator.of(context).pop(false);
                                      },
                                      child: const Text('Cancel'))
                                ],
                              );
                            }).then((value) {
                          if (value) {
                            activePlan.waypoints.clear();
                            Provider.of<Client>(context, listen: false).pushFlightPlan();
                          }
                        });
                        break;
                    }
                  },
                  itemBuilder: (context) => const <PopupMenuEntry<String>>[
                        PopupMenuItem(
                          value: "save",
                          child: ListTile(
                            leading: Icon(Icons.save_as),
                            title: Text("Save Plan"),
                          ),
                        ),
                        PopupMenuItem(
                          value: "clear",
                          child: ListTile(
                            leading: Icon(
                              Icons.delete_forever,
                              color: Colors.red,
                            ),
                            title: Text("Clear Waypoints"),
                          ),
                        ),
                      ]),
            ],
          ),

          Divider(
            thickness: 2,
            height: 1,
            color: Theme.of(context).backgroundColor,
          ),

          // --- Waypoint list
          Expanded(
            child: ReorderableListView.builder(
              // shrinkWrap: true,
              // primary: true,
              itemCount: activePlan.waypoints.length,
              itemBuilder: (context, i) => Slidable(
                key: ValueKey(activePlan.waypoints[i]),
                dragStartBehavior: DragStartBehavior.start,
                startActionPane: ActionPane(extentRatio: 0.15, motion: const ScrollMotion(), children: [
                  SlidableAction(
                    onPressed: (e) => {activePlan.removeWaypoint(i)},
                    icon: Icons.delete,
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ]),
                endActionPane: ActionPane(
                  extentRatio: 0.3,
                  motion: const ScrollMotion(),
                  children: [
                    SlidableAction(
                      onPressed: (e) {
                        editWaypoint(
                          context,
                          activePlan.waypoints[i],
                          // TODO
                          // editPointsCallback: () => onEditPoints(i),
                        )?.then((newWaypoint) {
                          if (newWaypoint != null) {
                            // --- Update selected waypoint
                            Provider.of<ActivePlan>(context, listen: false).updateWaypoint(
                                i, newWaypoint.name, newWaypoint.icon, newWaypoint.color, newWaypoint.latlng);
                          }
                        });
                      },
                      icon: Icons.edit,
                      backgroundColor: Colors.grey.shade400,
                      foregroundColor: Colors.black,
                    ),
                    SlidableAction(
                      onPressed: (e) {
                        showDialog<String>(
                            context: context,
                            builder: (context) => SimpleDialog(
                                  title: Text(Provider.of<Plans>(context, listen: false).loadedPlans.isEmpty
                                      ? "Oops, make a plan / collection in Waypoints menu first!"
                                      : "Save waypoint into:"),
                                  children: Provider.of<Plans>(context, listen: false)
                                      .loadedPlans
                                      .keys
                                      .map((name) => SimpleDialogOption(
                                          onPressed: () => Navigator.pop(context, name), child: Text(name)))
                                      .toList(),
                                )).then((value) {
                          if (value != null) {
                            Provider.of<Plans>(context, listen: false)
                                .loadedPlans[value]
                                ?.waypoints
                                .add(activePlan.waypoints[i]);
                          }
                        });
                      },
                      icon: Icons.playlist_add,
                      backgroundColor: Colors.grey.shade400,
                      foregroundColor: Colors.black,
                    )
                    // ReorderableDragStartListener(
                    //   index: i,
                    //   child: Container(
                    //     color: Colors.grey.shade400,
                    //     child: const Padding(
                    //       padding: EdgeInsets.all(16.0),
                    //       child: Icon(
                    //         Icons.drag_handle,
                    //         size: 24,
                    //         color: Colors.black,
                    //       ),
                    //     ),
                    //   ),
                    // ),
                  ],
                ),
                child: WaypointCard(
                  waypoint: activePlan.waypoints[i],
                  index: i,
                  onSelect: () {
                    debugPrint("Selected $i");
                    activePlan.selectWaypoint(i);
                  },
                  onDoubleTap: () {
                    // zoomMainMapToLatLng.sink.add(activePlan.waypoints[i].latlng[0]);
                  },
                  isSelected: i == activePlan.selectedIndex,
                ),
              ),
              onReorder: (oldIndex, newIndex) {
                debugPrint("WP order: $oldIndex --> $newIndex");
                activePlan.sortWaypoint(oldIndex, newIndex);
                Provider.of<Group>(context, listen: false).fixPilotSelectionsOnSort(oldIndex, newIndex);
              },
            ),
          ),
          // This shows when flight plan is empty
          if (activePlan.waypoints.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 50, bottom: 50),
              child: Text(
                "No waypoints added yet...",
                textAlign: TextAlign.center,
                style: instrLabel,
              ),
            ),
        ],
      );
    });
  }
}
