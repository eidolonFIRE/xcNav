import 'dart:async';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:provider/provider.dart';

// --- Dialogs
import 'package:xcnav/dialogs/edit_plan_name.dart';
import 'package:xcnav/dialogs/save_plan.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/plans.dart';

import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/widgets/make_path_barbs.dart';
import 'package:xcnav/widgets/map_marker.dart';
import 'package:xcnav/widgets/waypoint_card.dart';

class PlanCard extends StatefulWidget {
  final FlightPlan plan;

  const PlanCard(this.plan, {Key? key}) : super(key: key);

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  var formKey = GlobalKey<FormState>();
  bool isExpanded = false;
  Set<int> checkedElements = {};

  void deletePlan(BuildContext context) {
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: const Text('Please Confirm'),
            content: const Text('Are you sure you want to delete this plan?'),
            actions: [
              // The "Yes" button
              TextButton.icon(
                  onPressed: () {
                    Provider.of<Plans>(context, listen: false).deletePlan(widget.plan.name);
                    Navigator.popUntil(context, ModalRoute.withName("/plans"));
                  },
                  icon: const Icon(
                    Icons.delete_forever,
                    color: Colors.red,
                  ),
                  label: const Text('Delete')),
              TextButton(
                  onPressed: () {
                    // Close the dialog
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'))
            ],
          );
        });
  }

  void _replacePlan(BuildContext context) {
    final activePlan = Provider.of<ActivePlan>(context, listen: false);
    activePlan.waypoints.clear();
    activePlan.waypoints.addAll(widget.plan.waypoints);
    Provider.of<Client>(context, listen: false).pushFlightPlan();
    activePlan.isSaved = true;
  }

  void _replacePlanDialog(BuildContext context) {
    if (Provider.of<ActivePlan>(context, listen: false).waypoints.isNotEmpty) {
      savePlan(context, isSavingFirst: true).then((value) {
        _replacePlan(context);
      });
    } else {
      _replacePlan(context);
    }
  }

  void toggleItem(int index) {
    if (checkedElements.contains(index)) {
      checkedElements.remove(index);
    } else {
      checkedElements.add(index);
    }
  }

  Future<bool?> replacePlanDialog(BuildContext context) {
    return showDialog<bool?>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Please Confirm'),
            content: const Text('This will replace the plan for everyone in the group.'),
            actions: [
              // The "Yes" button
              ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  icon: const Icon(
                    Icons.check,
                    color: Colors.amber,
                  ),
                  label: const Text('Replace')),
              ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text('Cancel'))
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              // --- Title
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  widget.plan.goodFile ? widget.plan.name : "Broken File",
                  style: Theme.of(context)
                      .textTheme
                      .headline6!
                      .merge(TextStyle(color: widget.plan.goodFile ? Colors.white : Colors.red)),
                ),
              ),
              // --- Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      onPressed: () => {setState(() => isExpanded = !isExpanded)},
                      icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more)),
                  PopupMenuButton<String>(
                    onSelected: ((value) {
                      switch (value) {
                        case "replace":
                          if (Provider.of<Group>(context, listen: false).pilots.isNotEmpty) {
                            replacePlanDialog(context).then((value) {
                              if (value ?? false) _replacePlanDialog(context);
                            });
                          } else {
                            _replacePlanDialog(context);
                          }
                          break;
                        case "edit":
                          Navigator.pushNamed(context, "/planEditor", arguments: widget.plan);
                          break;
                        case "rename":
                          editPlanName(context, widget.plan.name).then((newName) {
                            if (newName != null && newName.isNotEmpty) {
                              final oldName = widget.plan.name;
                              Navigator.popUntil(context, ModalRoute.withName("/plans"));
                              Provider.of<Plans>(context, listen: false).renamePlan(oldName, newName);
                            }
                          });
                          break;
                        case "duplicate":
                          editPlanName(context, widget.plan.name).then((newName) {
                            if (newName != null && newName.isNotEmpty) {
                              final oldName = widget.plan.name;
                              Navigator.popUntil(context, ModalRoute.withName("/plans"));
                              Provider.of<Plans>(context, listen: false).duplicatePlan(oldName, newName);
                            }
                          });
                          break;
                        case "delete":
                          deletePlan(context);
                          break;
                        default:
                          debugPrint("Oops! Button not handled! $value");
                      }
                    }),
                    icon: const Icon(Icons.more_horiz),
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      // PopupMenuItem(
                      //   enabled: false,
                      //   height: 20,
                      //   child: Text(
                      //     "To the Active Plan:",
                      //   ),
                      // ),
                      // --- Option: Add
                      // PopupMenuItem(
                      //     value: "append",
                      //     child: ListTile(
                      //         title: Text(
                      //           "Activate Waypoints",
                      //           style: TextStyle(color: Colors.lightGreen, fontSize: 20),
                      //         ),
                      //         leading: Icon(
                      //           Icons.playlist_add,
                      //           size: 28,
                      //           color: Colors.lightGreen,
                      //         ))),
                      // --- Option: Replace
                      PopupMenuItem(
                          value: "replace",
                          child: ListTile(
                              title: Text(
                                "Use as Active Plan",
                                style: TextStyle(color: Colors.amber, fontSize: 20),
                              ),
                              leading: Icon(
                                Icons.playlist_remove,
                                size: 28,
                                color: Colors.amber,
                              ))),

                      PopupMenuDivider(),

                      // --- Option: Edit
                      PopupMenuItem(
                          value: "edit",
                          child: ListTile(
                              title: Text("Edit", style: TextStyle(fontSize: 20)),
                              leading: Icon(
                                Icons.pin_drop,
                                size: 28,
                                // color: Colors.blue,
                              ))),
                      // --- Option: Rename
                      PopupMenuItem(
                          value: "rename",
                          child: ListTile(
                            title: Text("Rename", style: TextStyle(fontSize: 20)),
                            leading: Icon(Icons.edit, size: 30),
                          )),
                      // --- Option: Duplicate
                      PopupMenuItem(
                          value: "duplicate",
                          child: ListTile(
                            title: Text("Duplicate", style: TextStyle(fontSize: 20)),
                            leading: Icon(
                              Icons.copy_all,
                              size: 28,
                            ),
                          )),

                      PopupMenuDivider(),

                      // --- Option: Delete
                      PopupMenuItem(
                          value: "delete",
                          child: ListTile(
                              title: Text(
                                "Delete",
                                style: TextStyle(color: Colors.red, fontSize: 20),
                              ),
                              leading: Icon(
                                Icons.delete,
                                size: 28,
                                color: Colors.red,
                              )))
                    ],
                  )
                ],
              )
            ],
          ),
          if (isExpanded)
            const Divider(
              height: 10,
            ),
          if (isExpanded)
            AspectRatio(
              // width: MediaQuery.of(context).size.width / 2,
              // height: MediaQuery.of(context).size.width / 2,
              aspectRatio: 1.5,
              child: FlutterMap(
                  options: MapOptions(
                    bounds: widget.plan.getBounds(),
                    interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    // allowPanningOnScrollingParent: false
                  ),
                  layers: [
                    // TileLayerOptions(
                    //   // urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                    //   // subdomains: ['a', 'b', 'c'],
                    //   urlTemplate:
                    //       'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
                    //   // tileSize: 512,
                    //   // zoomOffset: -1,
                    // ),
                    Provider.of<Settings>(context, listen: false).getMapTileLayer("topo"),

                    // Trip snake lines
                    PolylineLayerOptions(polylines: widget.plan.buildTripSnake()),

                    // Flight plan markers
                    PolylineLayerOptions(
                      polylines: widget.plan.waypoints
                          // .where((value) => value.latlng.length > 1)
                          .mapIndexed((i, e) => e.latlng.length > 1
                              ? Polyline(
                                  points: e.latlng,
                                  strokeWidth: checkedElements.contains(i) ? 6 : 3,
                                  color: e.getColor(),
                                  isDotted: e.isOptional)
                              : null)
                          .whereNotNull()
                          .toList(),
                    ),

                    // Flight plan paths - directional barbs
                    MarkerLayerOptions(markers: makePathBarbs(widget.plan.waypoints, false, 30)),

                    // Waypoint Markers
                    MarkerLayerOptions(
                      markers: widget.plan.waypoints
                          .mapIndexed((i, e) {
                            if (e.latlng.length == 1) {
                              final bool isChecked = checkedElements.contains(i);
                              return Marker(
                                  point: e.latlng[0],
                                  height: isChecked ? 40 : 30,
                                  width: (isChecked ? 40 : 30) * 2 / 3,
                                  builder: (context) => Container(
                                      transform: Matrix4.translationValues(0, isChecked ? (-15 * 4 / 3) : -15, 0),
                                      child: GestureDetector(
                                          onTap: () => setState(() => toggleItem(i)),
                                          child: MapMarker(e, isChecked ? 40 : 30))));
                            } else {
                              return null;
                            }
                          })
                          .whereNotNull()
                          .toList(),
                    ),
                  ]),
            ),
          if (isExpanded)
            Container(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: widget.plan.waypoints.length,
                  itemBuilder: (context, index) => WaypointCard(
                        index: index,
                        waypoint: widget.plan.waypoints[index],
                        onSelect: () {
                          setState(
                            () {
                              toggleItem(index);
                            },
                          );
                        },
                        onToggleOptional: () {},
                        isSelected: checkedElements.contains(index),
                        showPilots: false,
                      )),
            ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ElevatedButton.icon(
                  onPressed: () {
                    Provider.of<ActivePlan>(context, listen: false).waypoints.addAll(checkedElements.isEmpty
                        ? widget.plan.waypoints
                        : checkedElements.map((e) => widget.plan.waypoints[e]).toList());
                    Provider.of<Client>(context, listen: false).pushFlightPlan();
                    Navigator.popUntil(context, ModalRoute.withName("/home"));
                  },
                  icon: const Icon(
                    Icons.playlist_add,
                    color: Colors.lightGreen,
                  ),
                  label: Text(
                    "Activate ${checkedElements.isEmpty ? "All" : "Selected (${checkedElements.length})"}",
                    style: const TextStyle(fontSize: 18),
                  )),
            )
        ]),
      ),
    );
  }
}
