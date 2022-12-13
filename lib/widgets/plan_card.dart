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

// --- Misc
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/tappable_polyline.dart';
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
  Set<WaypointID> checkedElements = {};

  final mapController = MapController();
  bool mapReady = false;

  @override
  void initState() {
    super.initState();
  }

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
    Provider.of<Client>(context, listen: false).pushWaypoints();
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

  void toggleItem(WaypointID index) {
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    widget.plan.goodFile ? widget.plan.name : "Broken File",
                    style: Theme.of(context)
                        .textTheme
                        .headline6!
                        .merge(TextStyle(color: widget.plan.goodFile ? Colors.white : Colors.red)),
                    overflow: TextOverflow.ellipsis,
                  ),
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
                                "Replace All",
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
              child: Stack(
                children: [
                  FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                          onMapReady: () => setState(
                                () {
                                  debugPrint("Mapready");
                                  mapReady = true;
                                },
                              ),
                          bounds: widget.plan.getBounds(),
                          interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                      children: [
                        Provider.of<Settings>(context, listen: false).getMapTileLayer("topo"),

                        // Flight plan paths - Polyline
                        TappablePolylineLayer(
                          polylines: widget.plan.waypoints.values
                              .where(
                                (element) => element.isPath,
                              )
                              .map((e) => TaggedPolyline(
                                  points: e.latlng,
                                  tag: e.id,
                                  strokeWidth: checkedElements.contains(e.id) ? 6.0 : 3.0,
                                  color: e.getColor()))
                              .toList(),
                          onTap: (p0, tapPosition) {
                            if (p0.tag != null) {
                              setState(
                                () {
                                  toggleItem(p0.tag!);
                                },
                              );
                            }
                          },
                        ),

                        // Waypoint Markers
                        MarkerLayer(
                          markers: widget.plan.waypoints.values
                              .map((e) {
                                if (e.latlng.length == 1) {
                                  final bool isChecked = checkedElements.contains(e.id);
                                  return Marker(
                                      point: e.latlng[0],
                                      height: isChecked ? 40 : 30,
                                      width: (isChecked ? 40 : 30) * 2 / 3,
                                      builder: (context) => Container(
                                          transform: Matrix4.translationValues(0, isChecked ? (-15 * 4 / 3) : -15, 0),
                                          child: GestureDetector(
                                              onTap: () => setState(() => toggleItem(e.id)),
                                              child: MapMarker(e, isChecked ? 40 : 30))));
                                } else {
                                  return null;
                                }
                              })
                              .whereNotNull()
                              .toList(),
                        ),
                      ]),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: ElevatedButton.icon(
                          onPressed: () {
                            final plan = Provider.of<ActivePlan>(context, listen: false);
                            plan.waypoints.addAll(checkedElements.isEmpty
                                ? widget.plan.waypoints
                                : Map<WaypointID, Waypoint>.fromEntries(widget.plan.waypoints.entries
                                    .where((element) => checkedElements.contains(element.key))));
                            Provider.of<Client>(context, listen: false).pushWaypoints();
                            Navigator.popUntil(context, ModalRoute.withName("/home"));
                            plan.notifyListeners();
                          },
                          icon: const Icon(
                            Icons.playlist_add,
                            color: Colors.lightGreen,
                          ),
                          label: Text(
                            "Load ${checkedElements.isEmpty ? "All" : "Selected (${checkedElements.length})"}",
                            style: const TextStyle(fontSize: 18),
                          )),
                    ),
                  )
                ],
              ),
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
                        waypoint: widget.plan.waypoints.values.toList()[index],
                        onSelect: () {
                          setState(
                            () {
                              toggleItem(widget.plan.waypoints.values.toList()[index].id);
                            },
                          );
                        },
                        isSelected: checkedElements.contains(widget.plan.waypoints.values.toList()[index].id),
                        showPilots: false,
                      )),
            ),
        ]),
      ),
    );
  }
}
