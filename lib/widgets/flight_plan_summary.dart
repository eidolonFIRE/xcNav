import 'dart:io';
import 'package:flutter_map/plugin_api.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart';
import 'package:provider/provider.dart';

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/widgets/map_marker.dart';
import 'package:xcnav/widgets/waypoint_card.dart';
import 'package:xcnav/widgets/waypoint_card_readonly.dart';

class FlightPlanSummary extends StatefulWidget {
  final FlightPlan plan;
  final Function onDelete;
  late final LatLngBounds mapBounds;
  int? selectedIndex;

  FlightPlanSummary(this.plan, this.onDelete, {Key? key}) : super(key: key) {
    // TODO: handle lines
    mapBounds = LatLngBounds.fromPoints(
        plan.waypoints.map((e) => e.latlng[0]).toList());
    mapBounds.pad(0.4);
  }

  @override
  State<FlightPlanSummary> createState() => _FlightPlanSummaryState();
}

class _FlightPlanSummaryState extends State<FlightPlanSummary> {
  bool showList = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[700],
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              // --- Title
              Text(
                widget.plan.title,
                style: Theme.of(context).textTheme.headline5!.merge(TextStyle(
                    color: widget.plan.goodFile ? Colors.white : Colors.red)),
              ),
              // --- Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- Edit this plan
                  IconButton(
                      onPressed: () {
                        // final filename = plan.title;
                        // (Platform.isIOS
                        //         ? getApplicationDocumentsDirectory()
                        //         : Future(() =>
                        //             Directory('/storage/emulated/0/Documents')))
                        //     .then((Directory path) {
                        //   var outFile =
                        //       File(path.path + "/xcNav_kml/$filename.kml");
                        //   outFile.create(recursive: true).then(
                        //       (value) => value.writeAsString(plan.toKML()));
                        // });
                      },
                      icon: const Icon(Icons.edit)),
                  // --- Delete this plan
                  IconButton(
                      // iconSize: 20,
                      onPressed: () {
                        showDialog(
                            context: context,
                            builder: (BuildContext ctx) {
                              return AlertDialog(
                                title: const Text('Please Confirm'),
                                content: const Text(
                                    'Are you sure you want to delete this plan?'),
                                actions: [
                                  // The "Yes" button
                                  TextButton.icon(
                                      onPressed: () {
                                        // Delete Log File
                                        File planFile =
                                            File(widget.plan.filename);
                                        planFile.exists().then((value) {
                                          planFile.delete();
                                          Navigator.of(context).pop();
                                          widget.onDelete();
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
                      },
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.red,
                      ))
                ],
              )
            ],
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
                                      .mapIndexed((i, e) => Marker(
                                          // TODO: support lines
                                          point: e.latlng[0],
                                          height: i == widget.selectedIndex
                                              ? 40
                                              : 30,
                                          width: (i == widget.selectedIndex
                                                  ? 40
                                                  : 30) *
                                              2 /
                                              3,
                                          builder: (context) => Center(
                                              child: MapMarker(
                                                  e,
                                                  i == widget.selectedIndex
                                                      ? 40
                                                      : 30))))
                                      .toList(),
                                ),
                                // TODO: show other things like take-off, landing, and flight plan
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
                          columnWidths: const {
                            1: FlexColumnWidth(),
                            2: FlexColumnWidth()
                          },
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
                                  child: widget.plan.length > 1
                                      ? Text(
                                          "${(widget.plan.length * meter2Mile).toStringAsFixed(1)} mi",
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
                      widget.selectedIndex = i;
                    });
                  },
                  onAdd: () {
                    debugPrint("Add waypoint $i to active");
                    Provider.of<ActivePlan>(context, listen: false)
                        .insertWaypoint(
                            null,
                            widget.plan.waypoints[i].name,
                            widget.plan.waypoints[i].latlng[0],
                            widget.plan.waypoints[i].isOptional,
                            widget.plan.waypoints[i].icon,
                            widget.plan.waypoints[i].color);
                  },
                  isSelected: i == widget.selectedIndex,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
