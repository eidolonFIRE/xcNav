import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/widgets/map_marker.dart';
import 'package:xcnav/widgets/waypoint_card_readonly.dart';

class FlightPlanSummary extends StatefulWidget {
  final FlightPlan plan;
  final Function onDelete;
  late final LatLngBounds mapBounds;

  FlightPlanSummary(this.plan, this.onDelete, {Key? key}) : super(key: key) {
    List<LatLng> points = [];
    for (final wp in plan.waypoints) {
      points.addAll(wp.latlng);
    }

    mapBounds = LatLngBounds.fromPoints(points);
    mapBounds.pad(0.4);
  }

  @override
  State<FlightPlanSummary> createState() => _FlightPlanSummaryState();
}

class _FlightPlanSummaryState extends State<FlightPlanSummary> {
  bool showList = false;
  int? selectedIndex;
  var formKey = GlobalKey<FormState>();

  void deleteItem(BuildContext context) {
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
                        // Navigator.of(context).pop();
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

  void rename(BuildContext context) {
    TextEditingController filename = TextEditingController();
    filename.text = widget.plan.name;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Rename Plan"),
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
                      .rename(filename.text)
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
                    itemBuilder: (context) => [
                      // --- Option: Rename
                      PopupMenuItem(
                          child: TextButton.icon(
                              label: const Text("Rename"),
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                rename(context);
                              })),
                      // --- Option: Edit
                      PopupMenuItem(
                          child: TextButton.icon(
                              label: const Text("Edit"),
                              onPressed: () {},
                              icon: const Icon(
                                Icons.pin_drop,
                                // color: Colors.blue,
                              ))),
                      // --- Option: Delete
                      PopupMenuItem(
                          child: TextButton.icon(
                              label: const Text(
                                "Delete",
                                style: TextStyle(color: Colors.red),
                              ),
                              onPressed: () {
                                deleteItem(context);
                              },
                              icon: const Icon(
                                Icons.delete,
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
                          width: MediaQuery.of(context).size.width / 2.5,
                          height: MediaQuery.of(context).size.width / 2.5,
                          child: FlutterMap(
                              options: MapOptions(
                                interactiveFlags: InteractiveFlag.none,
                                bounds: widget.mapBounds,
                              ),
                              layers: [
                                TileLayerOptions(
                                  // urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                                  // subdomains: ['a', 'b', 'c'],
                                  urlTemplate:
                                      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
                                  // tileSize: 512,
                                  // zoomOffset: -1,
                                ),
                                MarkerLayerOptions(
                                  markers: widget.plan.waypoints
                                      // .where((value) => value.latlng.length == 1)
                                      .mapIndexed((i, e) => e.latlng.length == 1
                                          ? Marker(
                                              point: e.latlng[0],
                                              height: i == selectedIndex ? 40 : 30,
                                              width: (i == selectedIndex ? 40 : 30) * 2 / 3,
                                              builder: (context) =>
                                                  Center(child: MapMarker(e, i == selectedIndex ? 40 : 30)))
                                          : null)
                                      .whereNotNull()
                                      .toList(),
                                ),
                                // Flight plan markers

                                PolylineLayerOptions(
                                  polylines: widget.plan.waypoints
                                      // .where((value) => value.latlng.length > 1)
                                      .mapIndexed((i, e) => e.latlng.length > 1
                                          ? Polyline(
                                              points: e.latlng,
                                              strokeWidth: i == selectedIndex ? 6 : 4,
                                              color: Color(e.color ?? Colors.black.value))
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
                            // TableRow(children: [
                            //   const TableCell(child: Text("Duration")),
                            //   TableCell(
                            //       child:
                            //           //  plan.durationTime != null
                            //           //     ? Text(
                            //           //         "${plan.durationTime!.inHours}:${plan.durationTime!.inMinutes.toString().padLeft(2, "0")}",
                            //           //         textAlign: TextAlign.end,
                            //           //       )
                            //           //     :
                            //           Container())
                            // ]),
                            TableRow(children: [
                              const TableCell(child: Text("Total Length")),
                              TableCell(
                                  child: (widget.plan.length ?? 0) > 1
                                      ? Text(
                                          "${(widget.plan.length! * meters2Miles).toStringAsFixed(1)} mi",
                                          textAlign: TextAlign.end,
                                        )
                                      : Container()),
                            ]),
                          ],
                        ),
                      ),
                      // --- Append buttons
                      if (!showList)
                        IconButton(
                            onPressed: () => {
                                  setState(
                                    () => {showList = true},
                                  )
                                },
                            icon: const Icon(
                              Icons.playlist_add,
                              size: 30,
                              color: Colors.green,
                            )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showList)
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.plan.waypoints.length,
                itemBuilder: (context, i) => WaypointCardReadOnly(
                  key: ValueKey(widget.plan.waypoints[i]),
                  waypoint: widget.plan.waypoints[i],
                  index: i,
                  onSelect: () {
                    debugPrint("Selected $i");
                    setState(() {
                      selectedIndex = i;
                    });
                  },
                  onAdd: () {
                    debugPrint("Add waypoint $i to active");
                    var plan = Provider.of<ActivePlan>(context, listen: false);
                    plan.insertWaypoint(
                        plan.waypoints.length,
                        widget.plan.waypoints[i].name,
                        widget.plan.waypoints[i].latlng,
                        widget.plan.waypoints[i].isOptional,
                        widget.plan.waypoints[i].icon,
                        widget.plan.waypoints[i].color);
                  },
                  isSelected: i == selectedIndex,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
