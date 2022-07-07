import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/dialogs/save_plan.dart';

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
              ElevatedButton.icon(
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
              ElevatedButton(
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
      savePlan(context).then((value) {
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
    TextEditingController filename = TextEditingController();
    filename.text = widget.plan.name;

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(deleteOld ? "Rename Plan" : "Save Plan"),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: filename,
            validator: (value) {
              if (value != null) {
                if (value.trim().isEmpty || value.isEmpty) return "Must not be empty";
              }
              return null;
            },
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9_ -]"))],
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "plan name",
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 20),
          ),
        ),
        actions: [
          ElevatedButton.icon(
              label: const Text("Save"),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  widget.plan
                      .rename(filename.text, deleteOld: deleteOld)
                      .then((value) => Navigator.popUntil(context, ModalRoute.withName("/plans")));
                }
                setState(() {});
              },
              icon: const Icon(
                Icons.save,
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
      ),
    );
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
                  PopupMenuButton(
                    icon: const Icon(Icons.more_horiz),
                    itemBuilder: (context) => <PopupMenuEntry>[
                      // TODO: determine if this is still needed (or find something more elegant)
                      const PopupMenuItem(
                        enabled: false,
                        height: 20,
                        child: Text(
                          "To the Active Plan:",
                        ),
                      ),
                      // --- Option: Add All
                      PopupMenuItem(
                          child: TextButton.icon(
                              label: const Text(
                                "Append",
                                style: TextStyle(color: Colors.lightGreen),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                Provider.of<ActivePlan>(context, listen: false).waypoints.addAll(widget.plan.waypoints);
                                Provider.of<Client>(context, listen: false).pushFlightPlan();
                              },
                              icon: const Icon(
                                Icons.playlist_add,
                                size: 28,
                                color: Colors.lightGreen,
                              ))),
                      // --- Option: Replace
                      PopupMenuItem(
                          child: TextButton.icon(
                              label: const Text(
                                "Replace",
                                style: TextStyle(color: Colors.amber),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                if (Provider.of<Group>(context, listen: false).pilots.isNotEmpty) {
                                  replacePlanDialog(context).then((value) {
                                    if (value ?? false) _replacePlanDialog(context);
                                  });
                                } else {
                                  _replacePlanDialog(context);
                                }
                              },
                              icon: const Icon(
                                Icons.playlist_remove,
                                size: 28,
                                color: Colors.amber,
                              ))),

                      const PopupMenuDivider(),

                      // --- Option: Edit
                      PopupMenuItem(
                          child: TextButton.icon(
                              label: const Text("Edit"),
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pushNamed(context, "/planEditor", arguments: widget.plan);
                              },
                              icon: const Icon(
                                Icons.pin_drop,
                                size: 28,
                                // color: Colors.blue,
                              ))),
                      // --- Option: Rename
                      PopupMenuItem(
                          child: TextButton.icon(
                              label: const Text("Rename"),
                              icon: const Icon(Icons.edit, size: 30),
                              onPressed: () {
                                Navigator.pop(context);
                                rename(context);
                              })),
                      // --- Option: Duplicate
                      PopupMenuItem(
                          child: TextButton.icon(
                              label: const Text("Duplicate"),
                              icon: const Icon(
                                Icons.copy_all,
                                size: 28,
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                rename(context, deleteOld: false).then((value) => widget.onDelete());
                                // widget.onDelete();
                              })),

                      const PopupMenuDivider(),

                      // --- Option: Delete
                      PopupMenuItem(
                          child: TextButton.icon(
                              label: const Text(
                                "Delete",
                                style: TextStyle(color: Colors.red),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                deletePlan(context);
                              },
                              icon: const Icon(
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
