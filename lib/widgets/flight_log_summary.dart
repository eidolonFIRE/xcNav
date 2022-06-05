import 'dart:io';
import 'package:flutter_map/plugin_api.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:open_file/open_file.dart';

import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/units.dart';

class FlightLogSummary extends StatelessWidget {
  final FlightLog log;
  final Function onDelete;
  late final LatLngBounds mapBounds;

  FlightLogSummary(this.log, this.onDelete, {Key? key}) : super(key: key) {
    mapBounds = LatLngBounds.fromPoints(log.samples.map((e) => e.latLng).toList());
    mapBounds.pad(0.2);
    debugPrint("Built log: ${log.filename}");
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
              // --- Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: () {
                        final filename = DateFormat("yyyy_MM_dd_hh_mm")
                            .format(DateTime.fromMillisecondsSinceEpoch(log.samples[0].time));
                        (Platform.isIOS
                                ? getApplicationDocumentsDirectory()
                                : Future(() => Directory('/storage/emulated/0/Documents')))
                            .then((Directory path) {
                          var outFile = File(path.path + "/xcNav_kml/$filename.kml");
                          outFile
                              .create(recursive: true)
                              .then((value) => value.writeAsString(log.toKML()).then((value) => showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                        title: const Text("File Exported to:"),
                                        content: GestureDetector(
                                            onTap: () => OpenFile.open(outFile.path),
                                            child: Text(
                                              outFile.path,
                                              style: const TextStyle(
                                                  color: Colors.blue, decoration: TextDecoration.underline),
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
                      },
                      icon: const Icon(
                        Icons.download,
                        size: 24,
                      )),
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: () {
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
                      },
                      icon: const Icon(Icons.delete, color: Colors.red, size: 24))
                ],
              )
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
                      // TODO: show other things like take-off, landing, and flight plan
                    ]),
              ),

              // --- Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Table(
                    columnWidths: const {1: FlexColumnWidth(), 2: FlexColumnWidth()},
                    children: [
                      TableRow(children: [
                        const TableCell(child: Text("Duration")),
                        TableCell(
                            child: log.durationTime != null
                                ? Text(
                                    (log.durationTime!.inMilliseconds / 3600000).toStringAsFixed(1) + " hr",
                                    textAlign: TextAlign.end,
                                  )
                                : const Text(
                                    "?",
                                    textAlign: TextAlign.end,
                                  ))
                      ]),
                      TableRow(children: [
                        const TableCell(child: Text("Distance")),
                        TableCell(
                            child: log.durationDist != null
                                ? Text(
                                    convertDistValueCoarse(
                                                Provider.of<Settings>(context, listen: false).displayUnitsDist,
                                                log.durationDist!)
                                            .toStringAsFixed(1) +
                                        unitStrDistCoarse[
                                            Provider.of<Settings>(context, listen: false).displayUnitsDist]!,
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
                                ? Text(
                                    convertDistValueFine(Provider.of<Settings>(context, listen: false).displayUnitsDist,
                                                log.maxAlt!)
                                            .toStringAsFixed(1) +
                                        unitStrDistFine[
                                            Provider.of<Settings>(context, listen: false).displayUnitsDist]!,
                                    textAlign: TextAlign.end,
                                  )
                                : const Text(
                                    "?",
                                    textAlign: TextAlign.end,
                                  )),
                      ]),
                      const TableRow(children: [TableCell(child: Text("")), TableCell(child: Text(""))]),
                      const TableRow(children: [
                        TableCell(
                          child: Text("...Request what else you want to see here..."),
                        ),
                        TableCell(child: Text(""))
                      ])
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
