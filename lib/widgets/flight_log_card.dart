import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;

import 'package:xcnav/log_store.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

class FlightLogCard extends StatelessWidget {
  final String logKey;

  const FlightLogCard(this.logKey, {super.key});

  /// Recover waypoints from log and put them into a new flight plan.
  void restoreWaypoints(BuildContext context) {
    final log = logStore.logs[logKey]!;

    final String planName = "${"Flight".tr()}: ${log.title}";

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

  void exportLog(BuildContext context, String fileType) async {
    final log = logStore.logs[logKey]!;
    String outFilename = await log.export();
    if (context.mounted) {
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text("File Exported to:"),
                content: Text(
                  outFilename,
                ),
                actions: [
                  ElevatedButton.icon(
                    label: Text("btn.Open".tr()),
                    onPressed: () async {
                      var result = await OpenFile.open(outFilename);
                      debugPrint(result.message);
                      // NOTE: Workaround for "high risk" android permission missing
                      if (result.message.toUpperCase().contains('MANAGE_EXTERNAL_STORAGE')) {
                        debugPrint("Workaround to MANAGE_EXTERNAL_STORAGE... using temp directory");
                        final tempFilename = p.basename(outFilename);
                        final String newpath = '${(await getTemporaryDirectory()).path}/$tempFilename';
                        await File(outFilename).copy(newpath);
                        result = await OpenFile.open(newpath);
                      }
                    },
                    icon: const Icon(
                      Icons.launch,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ));
    }
  }

  void deleteLog(BuildContext context) {
    // Delete the log file!
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: Text('dialog.confirm.please'.tr()),
            content: Text('dialog.confirm.delete_log'.tr()),
            actions: [
              // The "btn.Yes" button
              ElevatedButton.icon(
                  onPressed: () {
                    // Delete Log File
                    logStore.deleteLog(logKey);
                    Navigator.pop(context);
                  },
                  icon: const Icon(
                    Icons.delete_forever,
                    color: Colors.red,
                  ),
                  label: Text('btn.Delete'.tr())),
              // ElevatedButton(
              //     onPressed: () {
              //       // Close the dialog
              //       Navigator.of(context).pop();
              //     },
              //     child: const Text('Cancel'))
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    MapController mapController = MapController();
    LatLngBounds? mapBounds;

    final log = logStore.logs[logKey]!;

    if (log.goodFile) {
      mapBounds = log.getBounds(pad: 0.2);
    }

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: log.goodFile ? 200 : null,
          child: Stack(children: [
            if (log.goodFile)
              Builder(builder: (context) {
                return FlutterMap(
                    key: GlobalKey(debugLabel: "flight_log_card:${log.startTime?.millisecondsSinceEpoch.toString()}"),
                    mapController: mapController,
                    options: MapOptions(
                      initialCameraFit: mapBounds != null ? CameraFit.bounds(bounds: mapBounds) : null,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      onTap: (_, __) {
                        if (log.goodFile) {
                          Navigator.pushNamed(context, "/logReplay", arguments: {"logKey": logKey});
                        }
                      },
                    ),
                    children: [
                      getMapTileLayer(MapTileSrc.topo),

                      // --- Waypoints: paths
                      PolylineLayer(
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
                                child: Container(
                                    transformAlignment: const Alignment(0, 0),
                                    transform: Matrix4.translationValues(0, -30 * 0.5, 0),
                                    child: WaypointMarker(e, 60 * 0.5))))
                            .toList(),
                      ),

                      // --- Log Line
                      PolylineLayer(polylines: [
                        Polyline(
                          points: log.samples.map((e) => e.latlng).toList(),
                          strokeWidth: 4,
                          color: Colors.red,
                          pattern: const StrokePattern.dotted(),
                        )
                      ]),
                    ]);
              }),

            // --- info overlay
            if (log.goodFile)
              Positioned(
                right: 8,
                bottom: 4,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: log.startTime != null ? DateFormat("h:mm a").format(log.startTimeOriginal!) : "-"),
                    const TextSpan(text: "  ( "),
                    richHrMin(duration: log.durationTime),
                    const TextSpan(text: " )  "),
                    TextSpan(
                      text: log.endTime != null ? DateFormat("h:mm a").format(log.endTimeOriginal!) : "-",
                    )
                  ]),
                  style: const TextStyle(color: Colors.black),
                  textAlign: TextAlign.center,
                ),
              ),

            // --- Title bar
            Container(
              color: Colors.white54,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                // mainAxisSize: MainAxisSize.max,
                children: [
                  // --- Title
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        log.title,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 6,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge!
                            .merge(TextStyle(color: log.goodFile ? Colors.black : Colors.red)),
                      ),
                    ),
                  ),
                  if (log.imported != null)
                    Text(
                      "Imported from: ${log.imported!}",
                      style: const TextStyle(color: Colors.red),
                    ),
                  PopupMenuButton(
                      icon: const Icon(
                        Icons.more_vert,
                        color: Colors.black,
                      ),
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

                          case "export_json":
                            exportLog(context, "json");
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
                                  child:
                                      ListTile(leading: Icon(Icons.place, size: 28), title: Text("Recover Waypoints"))),
                            const PopupMenuItem(
                                enabled: false,
                                child: Padding(
                                  padding: EdgeInsets.only(left: 16),
                                  child: Text("Export Options:"),
                                )),
                            if (log.goodFile)
                              const PopupMenuItem(
                                  value: "export_kml",
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.file_download,
                                      size: 28,
                                    ),
                                    title: Text.rich(TextSpan(children: [
                                      TextSpan(text: "KML ", style: TextStyle(fontSize: 20)),
                                      TextSpan(
                                          text: "(Google Earth)", style: TextStyle(fontSize: 20, color: Colors.grey))
                                    ])),
                                  )),
                            if (log.goodFile)
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
                            const PopupMenuItem(
                                value: "export_json",
                                child: ListTile(
                                  leading: Icon(
                                    Icons.file_download,
                                    size: 28,
                                  ),
                                  title: Text.rich(TextSpan(children: [
                                    TextSpan(text: "Json ", style: TextStyle(fontSize: 20)),
                                    TextSpan(text: "(raw file)", style: TextStyle(fontSize: 20, color: Colors.grey))
                                  ])),
                                )),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                                value: "delete",
                                child: ListTile(
                                  leading: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: 28,
                                  ),
                                  title: Text("btn.Delete".tr(), style: TextStyle(fontSize: 20)),
                                ))
                          ])
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
