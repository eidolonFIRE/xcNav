import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/dialogs/edit_plan_name.dart';
import 'package:xcnav/dialogs/save_plan.dart';
import 'package:xcnav/dialogs/select_waypoints.dart';

// --- Models
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/make_path_barbs.dart';
import 'package:xcnav/widgets/map_marker.dart';

class PlanCard extends StatefulWidget {
  final FlightPlan plan;
  final Function onDelete;

  const PlanCard(this.plan, this.onDelete, {Key? key}) : super(key: key);

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  var formKey = GlobalKey<FormState>();

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
                    // Delete the file
                    widget.plan.getFilename().then((filename) {
                      File planFile = File(filename);
                      planFile.exists().then((value) {
                        planFile.delete();
                        widget.onDelete();
                      });
                      Navigator.popUntil(context, ModalRoute.withName("/plans"));
                    });
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

  Future rename(BuildContext context, {bool deleteOld = true}) {
    // TextEditingController filename = TextEditingController();
    // filename.text = widget.plan.name;
    Completer completer = Completer();
    editPlanName(context, widget.plan.name).then((newName) {
      if (newName != null && newName.isNotEmpty) {
        widget.plan
            .rename(newName, deleteOld: deleteOld)
            .then((_) => Navigator.popUntil(context, ModalRoute.withName("/plans")))
            .then((value) => completer.complete());
      } else {
        completer.complete();
      }
    });
    return completer.future;
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
                  PopupMenuButton<String>(
                    onSelected: ((value) {
                      switch (value) {
                        case "append":
                          selectWaypoints(context, widget.plan.waypoints).then((selected) {
                            Provider.of<ActivePlan>(context, listen: false).waypoints.addAll(selected ?? []);
                            Provider.of<Client>(context, listen: false).pushFlightPlan();
                          });

                          break;
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
                          rename(context).then((value) => setState(
                                () {},
                              ));

                          break;
                        case "duplicate":
                          rename(context, deleteOld: false).then((value) => widget.onDelete()).then((value) => setState(
                                () {},
                              ));

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
                      PopupMenuItem(
                          value: "append",
                          child: ListTile(
                              title: Text(
                                "Activate Waypoints",
                                style: TextStyle(color: Colors.lightGreen, fontSize: 20),
                              ),
                              leading: Icon(
                                Icons.playlist_add,
                                size: 28,
                                color: Colors.lightGreen,
                              ))),
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
          const Divider(
            height: 10,
          ),
          IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                // --- Preview Image
                Column(
                  children: [
                    Card(
                        color: Colors.white,
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width / 2,
                          height: MediaQuery.of(context).size.width / 2,
                          child: FlutterMap(
                              options: MapOptions(
                                  interactiveFlags: InteractiveFlag.none,
                                  bounds: widget.plan.getBounds(),
                                  allowPanningOnScrollingParent: false),
                              layers: [
                                TileLayerOptions(
                                  // urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                                  // subdomains: ['a', 'b', 'c'],
                                  urlTemplate:
                                      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
                                  // tileSize: 512,
                                  // zoomOffset: -1,
                                ),

                                // Trip snake lines
                                PolylineLayerOptions(polylines: widget.plan.buildTripSnake()),

                                // Flight plan markers
                                PolylineLayerOptions(
                                  polylines: widget.plan.waypoints
                                      // .where((value) => value.latlng.length > 1)
                                      .mapIndexed((i, e) => e.latlng.length > 1
                                          ? Polyline(
                                              points: e.latlng,
                                              strokeWidth: 4,
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
                                      .mapIndexed((i, e) => e.latlng.length == 1
                                          ? Marker(
                                              point: e.latlng[0],
                                              height: 30,
                                              width: 30 * 2 / 3,
                                              builder: (context) => Container(
                                                  transform: Matrix4.translationValues(0, -15, 0),
                                                  child: MapMarker(e, 30)))
                                          : null)
                                      .whereNotNull()
                                      .toList(),
                                ),
                              ]),
                        )),
                  ],
                ),

                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // --- Info
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Table(
                          columnWidths: const {0: FlexColumnWidth(), 1: FlexColumnWidth()},
                          children: [
                            TableRow(children: [
                              const TableCell(child: Text("Total Length")),
                              TableCell(
                                  child: (widget.plan.length) > 1
                                      ? Text.rich(
                                          TextSpan(children: [
                                            TextSpan(
                                                text: convertDistValueCoarse(
                                                        Provider.of<Settings>(context, listen: false).displayUnitsDist,
                                                        widget.plan.length)
                                                    .toStringAsFixed(1)),
                                            TextSpan(
                                                text: unitStrDistCoarse[
                                                    Provider.of<Settings>(context, listen: false).displayUnitsDist]),
                                          ]),
                                          textAlign: TextAlign.end,
                                        )
                                      : Container()),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
