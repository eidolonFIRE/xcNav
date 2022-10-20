import 'dart:io';
import 'package:flutter_map/plugin_api.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';

class FlightLogSummary extends StatelessWidget {
  final FlightLog log;
  final Function onDelete;
  late final LatLngBounds mapBounds;

  final dateFormat = DateFormat("h:mm a");
  static const unitStyle = TextStyle(color: Colors.grey, fontSize: 12);

  FlightLogSummary(this.log, this.onDelete, {Key? key}) : super(key: key) {
    mapBounds = LatLngBounds.fromPoints(log.samples.map((e) => e.latLng).toList());
    mapBounds.pad(0.2);
    debugPrint("Built log: ${log.filename}");
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
                    content: GestureDetector(
                        onTap: () => OpenFilex.open(outFile.path),
                        child: Text(
                          outFile.path,
                          style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                        )),
                    actions: [
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              // --- Title
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  log.title,
                  style: Theme.of(context)
                      .textTheme
                      .headline6!
                      .merge(TextStyle(color: log.goodFile ? Colors.white : Colors.red)),
                ),
              ),
              PopupMenuButton(
                  onSelected: (value) {
                    switch (value) {
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
                  itemBuilder: (context) => const <PopupMenuEntry<String>>[
                        PopupMenuItem(
                            enabled: false,
                            child: Padding(
                              padding: EdgeInsets.only(left: 16),
                              child: Text("Export Options:"),
                            )),
                        PopupMenuItem(
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
                        PopupMenuItem(
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
                        PopupMenuDivider(),
                        PopupMenuItem(
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
          const Divider(height: 10),
          Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              // --- Preview Image
              SizedBox(
                width: MediaQuery.of(context).size.width / 2.5,
                height: MediaQuery.of(context).size.width / 2.5,
                child: FlutterMap(
                    // mapController: mapController,
                    options: MapOptions(
                      interactiveFlags: InteractiveFlag.none,
                      bounds: mapBounds,
                      // center: mapBounds.center,
                      // zoom: mapBounds,
                      allowPanningOnScrollingParent: false,
                      allowPanning: false,
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
                      PolylineLayerOptions(polylines: [
                        Polyline(
                            points: log.samples.map((e) => e.latLng).toList(),
                            strokeWidth: 3,
                            color: Colors.red,
                            isDotted: false)
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
                                TextSpan(
                                    text:
                                        "  ${dateFormat.format(DateTime.fromMillisecondsSinceEpoch(log.samples.first.time))}"),
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
                                  text:
                                      "  ${dateFormat.format(DateTime.fromMillisecondsSinceEpoch(log.samples.last.time))}",
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
                            child: log.durationTime != null
                                ? Text.rich(
                                    richHrMin(
                                        duration: log.durationTime,
                                        longUnits: true,
                                        valueStyle: Theme.of(context).textTheme.bodyMedium!,
                                        unitStyle: unitStyle),
                                    textAlign: TextAlign.end)
                                : const Text(
                                    "?",
                                    textAlign: TextAlign.end,
                                  ))
                      ]),
                      TableRow(children: [
                        const TableCell(child: Text("Distance")),
                        TableCell(
                            child: log.durationDist != null
                                ? Text.rich(
                                    richValue(UnitType.distCoarse, log.durationDist!,
                                        decimals: 1, unitStyle: unitStyle),
                                    textAlign: TextAlign.end,
                                  )
                                : const Text(
                                    "?",
                                    textAlign: TextAlign.end,
                                  )),
                      ]),
                      TableRow(children: [
                        const TableCell(child: Text("Avg Speed")),
                        TableCell(
                            child: log.meanSpd != null
                                ? Text.rich(
                                    richValue(UnitType.speed, log.meanSpd!, decimals: 1, unitStyle: unitStyle),
                                    textAlign: TextAlign.end,
                                  )
                                : const Text(
                                    "?",
                                    textAlign: TextAlign.end,
                                  )),
                      ]),
                      TableRow(children: [
                        const TableCell(child: Text("Max Altitude")),
                        TableCell(
                            child: log.maxAlt != null
                                ? Text.rich(
                                    richValue(UnitType.distFine, log.maxAlt!, decimals: 1, unitStyle: unitStyle),
                                    textAlign: TextAlign.end,
                                  )
                                : const Text(
                                    "?",
                                    textAlign: TextAlign.end,
                                  )),
                      ]),
                      TableRow(children: [
                        const TableCell(child: Text("Best 1min Climb")),
                        TableCell(
                            child: log.bestClimb != null
                                ? Text.rich(
                                    richValue(UnitType.vario, log.bestClimb!, decimals: 1, unitStyle: unitStyle),
                                    textAlign: TextAlign.end,
                                  )
                                : const Text(
                                    "?",
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
