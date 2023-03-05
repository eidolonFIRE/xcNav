import 'dart:io';
import 'package:better_open_file/better_open_file.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

class FlightLogSummary extends StatelessWidget {
  final FlightLog log;
  final Function onDelete;
  late final LatLngBounds? mapBounds;

  final dateFormat = DateFormat("h:mm a");
  static const unitStyle = TextStyle(color: Colors.grey, fontSize: 12);

  FlightLogSummary(this.log, this.onDelete, {Key? key}) : super(key: key) {
    if (log.goodFile) {
      mapBounds = LatLngBounds.fromPoints(log.samples.map((e) => e.latlng).toList());
      for (final each in log.waypoints) {
        mapBounds!.extendBounds(LatLngBounds.fromPoints(each.latlng));
      }
      mapBounds!.pad(0.2);
    }
    debugPrint("Built log: ${log.filename} ${log.goodFile ? "" : "--BAD"}");
  }

  /// Recover waypoints from log and put them into a new flight plan.
  void restoreWaypoints(BuildContext context) {
    final String planName = "Flight: ${log.title}";

    final newPlan = FlightPlan(planName);
    for (final wp in log.waypoints) {
      newPlan.waypoints[wp.id] = wp;
    }

    Provider.of<Plans>(context, listen: false).setPlan(newPlan);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Exported to library under:",
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  "\"${newPlan.name}\"",
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(
                  Icons.check,
                  size: 20,
                  color: Colors.lightGreen,
                ))
          ],
        );
      },
    );
  }

  void exportLog(BuildContext context, String fileType) {
    final filename = DateFormat("yyyy_MM_dd_hh_mm").format(DateTime.fromMillisecondsSinceEpoch(log.samples[0].time));
    (Platform.isIOS ? getApplicationDocumentsDirectory() : Future(() => Directory('/storage/emulated/0/Documents')))
        .then((Directory path) {
      var outFile = File("${path.path}/xcNav_$fileType/$filename.$fileType");
      outFile.create(recursive: true).then(
          (value) => value.writeAsString(fileType == "kml" ? log.toKML() : log.toGPX()).then((value) => showDialog(
              context: context,
              builder: (context) => AlertDialog(
                    title: const Text("File Exported to:"),
                    content: Text(
                      outFile.path,
                    ),
                    actions: [
                      IconButton(
                        onPressed: () async {
                          var result = await OpenFile.open(outFile.path);
                          debugPrint(result.message);
                          // NOTE: Workaround for "high risk" android permission missing
                          if (result.message.toUpperCase().contains('MANAGE_EXTERNAL_STORAGE')) {
                            final filename = outFile.path.split('/').last;
                            final String newpath = '${(await getTemporaryDirectory()).path}/$filename';
                            await File(outFile.path).copy(newpath);
                            result = await OpenFile.open(newpath);
                          }
                        },
                        icon: const Icon(Icons.launch),
                        color: Colors.blue,
                      ),
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.check,
                            color: Colors.green,
                          ))
                    ],
                  ))));
    });
  }

  void deleteLog(BuildContext context) {
    // Delete the log file!
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: const Text('Please Confirm'),
            content: const Text('Are you sure you want to delete this log?'),
            actions: [
              // The "Yes" button
              TextButton.icon(
                  onPressed: () {
                    // Delete Log File
                    File logFile = File(log.filename);
                    logFile.exists().then((value) {
                      logFile.delete();
                      Navigator.of(context).pop();
                      onDelete();
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

  @override
  Widget build(BuildContext context) {
    MapController mapController = MapController();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            // mainAxisSize: MainAxisSize.max,
            children: [
              // --- Title
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    log.title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 6,
                    style: Theme.of(context)
                        .textTheme
                        .headline6!
                        .merge(TextStyle(color: log.goodFile ? Colors.white : Colors.red)),
                  ),
                ),
              ),
              PopupMenuButton(
                  onSelected: (value) {
                    switch (value) {
                      case "restore_waypoints":
                        restoreWaypoints(context);
                        break;

                      case "export_kml":
                        exportLog(context, "kml");
                        break;

                      case "export_gpx":
                        exportLog(context, "gpx");
                        break;

                      case "delete":
                        deleteLog(context);
                        break;
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                        if (log.waypoints.isNotEmpty)
                          const PopupMenuItem(
                              value: "restore_waypoints",
                              child: ListTile(leading: Icon(Icons.place, size: 28), title: Text("Recover Waypoints"))),
                        const PopupMenuItem(
                            enabled: false,
                            child: Padding(
                              padding: EdgeInsets.only(left: 16),
                              child: Text("Export Options:"),
                            )),
                        const PopupMenuItem(
                            value: "export_kml",
                            child: ListTile(
                              leading: Icon(
                                Icons.file_download,
                                size: 28,
                              ),
                              title: Text.rich(TextSpan(children: [
                                TextSpan(text: "KML ", style: TextStyle(fontSize: 20)),
                                TextSpan(text: "(Google Earth)", style: TextStyle(fontSize: 20, color: Colors.grey))
                              ])),
                            )),
                        const PopupMenuItem(
                            value: "export_gpx",
                            child: ListTile(
                              leading: Icon(
                                Icons.file_download,
                                size: 28,
                              ),
                              title: Text.rich(TextSpan(children: [
                                TextSpan(text: "GPX ", style: TextStyle(fontSize: 20)),
                                TextSpan(text: "(Ayvri.com)", style: TextStyle(fontSize: 20, color: Colors.grey))
                              ])),
                            )),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                            value: "delete",
                            child: ListTile(
                              leading: Icon(
                                Icons.delete,
                                color: Colors.red,
                                size: 28,
                              ),
                              title: Text("Delete", style: TextStyle(fontSize: 20)),
                            ))
                      ])
            ],
          ),
          if (log.goodFile) const Divider(height: 10),
          if (log.goodFile)
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                // --- Preview Image
                SizedBox(
                  width: MediaQuery.of(context).size.width / 2.5,
                  height: MediaQuery.of(context).size.width / 2.5,
                  child: FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        onMapReady: () {
                          if (mapBounds != null) {
                            mapController.fitBounds(mapBounds!);
                          }
                        },
                        interactiveFlags: InteractiveFlag.none,
                        // bounds: mapBounds,
                      ),
                      children: [
                        Provider.of<Settings>(context, listen: false).getMapTileLayer("topo"),

                        // --- Waypoints: paths
                        PolylineLayer(
                          polylineCulling: true,
                          polylines: log.waypoints
                              .where((value) => value.latlng.length > 1)
                              .map((e) => Polyline(points: e.latlng, strokeWidth: 3.0, color: e.getColor()))
                              .toList(),
                        ),

                        // --- Waypoints: pin markers
                        MarkerLayer(
                          markers: log.waypoints
                              .where((element) => element.latlng.length == 1)
                              .map((e) => Marker(
                                  point: e.latlng[0],
                                  height: 60 * 0.5,
                                  width: 40 * 0.5,
                                  builder: (context) => Container(
                                      transformAlignment: const Alignment(0, 0),
                                      transform: Matrix4.translationValues(0, -30 * 0.5, 0),
                                      child: WaypointMarker(e, 60 * 0.5))))
                              .toList(),
                        ),

                        // --- Log Line
                        PolylineLayer(polylines: [
                          Polyline(
                              points: log.samples.map((e) => e.latlng).toList(),
                              strokeWidth: 3,
                              color: Colors.red,
                              isDotted: true)
                        ]),
                      ]),
                ),

                // --- Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Table(
                      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
                      children: [
                        TableRow(children: [
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Text.rich(
                                TextSpan(children: [
                                  const WidgetSpan(
                                      child: Icon(
                                    Icons.flight_takeoff,
                                    size: 18,
                                  )),
                                  TextSpan(text: "  ${dateFormat.format(log.startTime)}"),
                                ]),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Text.rich(
                                TextSpan(children: [
                                  const WidgetSpan(child: Icon(Icons.flight_land, size: 18)),
                                  TextSpan(
                                    text: "  ${dateFormat.format(log.endTime)}",
                                  )
                                ]),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        ]),
                        TableRow(children: [
                          const TableCell(child: Text("Duration")),
                          TableCell(
                              child: Text.rich(
                                  richHrMin(
                                      duration: log.durationTime,
                                      longUnits: true,
                                      valueStyle: Theme.of(context).textTheme.bodyMedium!,
                                      unitStyle: unitStyle),
                                  textAlign: TextAlign.end))
                        ]),
                        TableRow(children: [
                          const TableCell(child: Text("Distance")),
                          TableCell(
                              child: Text.rich(
                            richValue(UnitType.distCoarse, log.durationDist, decimals: 1, unitStyle: unitStyle),
                            textAlign: TextAlign.end,
                          )),
                        ]),
                        TableRow(children: [
                          const TableCell(child: Text("Avg Speed")),
                          TableCell(
                              child: Text.rich(
                            richValue(UnitType.speed, log.meanSpd, decimals: 1, unitStyle: unitStyle),
                            textAlign: TextAlign.end,
                          )),
                        ]),
                        TableRow(children: [
                          const TableCell(child: Text("Max Altitude")),
                          TableCell(
                              child: Text.rich(
                            richValue(UnitType.distFine, log.maxAlt, decimals: 1, unitStyle: unitStyle),
                            textAlign: TextAlign.end,
                          )),
                        ]),
                        TableRow(children: [
                          const TableCell(child: Text("Best 1min Climb")),
                          TableCell(
                              child: Text.rich(
                            richValue(UnitType.vario, log.bestClimb, decimals: 1, unitStyle: unitStyle),
                            textAlign: TextAlign.end,
                          )),
                        ]),
                        // const TableRow(children: [TableCell(child: Text("")), TableCell(child: Text(""))]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ]),
      ),
    );
  }
}
