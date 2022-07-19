import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';
import 'package:flutter_map_dragmarker/dragmarker.dart';
import 'package:flutter_map_line_editor/polyeditor.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/dialogs/edit_latlng.dart';

// --- Models
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/my_telemetry.dart';

// --- Misc
import 'package:xcnav/screens/home.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/dialogs/edit_waypoint.dart';

// --- Providers
import 'package:xcnav/providers/settings.dart';

// --- Widgets
import 'package:xcnav/widgets/waypoint_card.dart';
import 'package:xcnav/widgets/make_path_barbs.dart';
import 'package:xcnav/widgets/map_marker.dart';

class PlanEditor extends StatefulWidget {
  const PlanEditor({Key? key}) : super(key: key);

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  int? selectedIndex;
  LatLngBounds? mapBounds;
  FlightPlan? plan;
  MapController mapController = MapController();
  int? editingIndex;
  late PolyEditor polyEditor;
  final List<LatLng> editablePolyline = [];

  FocusMode focusMode = FocusMode.unlocked;

  @override
  void initState() {
    super.initState();

    polyEditor = PolyEditor(
      addClosePathMarker: false,
      points: editablePolyline,
      pointIcon: const Icon(
        Icons.crop_square,
        size: 22,
        color: Colors.black,
      ),
      intermediateIcon: const Icon(Icons.circle_outlined, size: 12, color: Colors.black),
      callbackRefresh: () => {setState(() {})},
    );
  }

  @override
  void dispose() {
    plan?.saveToFile();
    super.dispose();
  }

  void setFocusMode(FocusMode mode) {
    setState(() {
      focusMode = mode;
      debugPrint("FocusMode = $mode");
    });
  }

  void beginEditingPolyline(int? index) {
    setState(() {
      editingIndex = index;
      editablePolyline.clear();
      if (index != null) {
        focusMode = FocusMode.editPath;
        editablePolyline.addAll(plan!.waypoints[index].latlng.toList());
      } else {
        focusMode = FocusMode.unlocked;
      }
    });
  }

  void finishEditingPolyline() {
    setState(() {
      if (editingIndex != null && editablePolyline.isNotEmpty) {
        plan!.waypoints[editingIndex!].latlng = editablePolyline.toList();
        plan!.refreshLength();
      } else {
        plan!.waypoints.removeAt(editingIndex!);
      }
      editingIndex = null;
      editablePolyline.clear();
      focusMode = FocusMode.unlocked;
      selectedIndex = null;
    });
  }

  void onMapTap(BuildContext context, LatLng latlng) {
    debugPrint("onMapTap: $latlng");
    if (focusMode == FocusMode.addWaypoint) {
      // --- Finish adding waypoint pin
      setFocusMode(FocusMode.unlocked);
      editWaypoint(context, Waypoint("", [latlng], false, null, null), isNew: true)?.then((newWaypoint) {
        if (newWaypoint != null) {
          setState(() {
            plan!.waypoints.add(newWaypoint);
          });
        }
      });
    } else if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath) {
      // --- Add waypoint in path
      polyEditor.add(editablePolyline, latlng);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (plan == null) {
      plan = ModalRoute.of(context)!.settings.arguments as FlightPlan;
      mapBounds = plan!.getBounds() ??
          (LatLngBounds.fromPoints([
            Provider.of<MyTelemetry>(context, listen: false).geo.latLng,
            Provider.of<MyTelemetry>(context, listen: false).geo.latLng..longitude += 0.05
          ])
            ..pad(2));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Plan"),
      ),
      body: Stack(
        children: [
              FlutterMap(
                  key: const Key("planEditorMap"),
                  options: MapOptions(
                    controller: mapController,
                    interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    // interactiveFlags: InteractiveFlag.none,
                    bounds: mapBounds,
                    allowPanningOnScrollingParent: false,
                    plugins: [
                      DragMarkerPlugin(),
                    ],
                    onTap: (tapPos, latlng) => onMapTap(context, latlng),
                  ),
                  layers: [
                    TileLayerOptions(
                      urlTemplate:
                          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
                    ),

                    // Trip snake lines
                    PolylineLayerOptions(polylines: plan!.buildTripSnake()),

                    // Flight plan markers
                    PolylineLayerOptions(
                      polylines: plan!.waypoints
                          // .where((value) => value.latlng.length > 1)
                          .mapIndexed((i, e) => e.latlng.length > 1 && i != editingIndex
                              ? Polyline(
                                  points: e.latlng,
                                  strokeWidth: i == selectedIndex ? 6 : 4,
                                  color: e.getColor(),
                                  isDotted: e.isOptional)
                              : null)
                          .whereNotNull()
                          .toList(),
                    ),

                    // Flight plan paths - directional barbs
                    MarkerLayerOptions(
                        markers: makePathBarbs(
                            editingIndex != null
                                ? (plan!.waypoints.toList()
                                  ..removeAt(editingIndex!)
                                  ..add(Waypoint(plan!.waypoints[editingIndex!].name, editablePolyline, false, null,
                                      plan!.waypoints[editingIndex!].color)))
                                : plan!.waypoints,
                            false,
                            40)),

                    // Flight plan markers
                    DragMarkerPluginOptions(
                        markers: plan!.waypoints
                            .mapIndexed((i, e) => e.latlng.length == 1
                                ? DragMarker(
                                    point: e.latlng[0],
                                    height: 60 * (i == selectedIndex ? 0.8 : 0.6),
                                    width: 40 * (i == selectedIndex ? 0.8 : 0.6),
                                    offset: Offset(0, -30 * (i == selectedIndex ? 0.8 : 0.6)),
                                    feedbackOffset: Offset(0, -30 * (i == selectedIndex ? 0.8 : 0.6)),
                                    onTap: (_) => {selectedIndex = i},
                                    onDragEnd: (p0, p1) {
                                      setState(() {
                                        plan!.waypoints[i].latlng = [p1];
                                        plan!.refreshLength();
                                      });
                                    },
                                    builder: (context) => MapMarker(e, 60 * (i == selectedIndex ? 0.8 : 0.6)))
                                : null)
                            .whereNotNull()
                            .toList()),

                    // Draggable line editor
                    if (editingIndex != null)
                      PolylineLayerOptions(polylines: [
                        Polyline(
                            color: plan!.waypoints[editingIndex!].getColor(), points: editablePolyline, strokeWidth: 5)
                      ]),
                    if (editingIndex != null) DragMarkerPluginOptions(markers: polyEditor.edit()),
                  ]),

              // --- Map overlay layers
              if (focusMode == FocusMode.addWaypoint)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Card(
                    color: Colors.amber.shade400,
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text.rich(
                        TextSpan(children: [
                          WidgetSpan(
                              child: Icon(
                            Icons.touch_app,
                            size: 18,
                            color: Colors.black,
                          )),
                          TextSpan(text: "Tap to place waypoint")
                        ]),
                        style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
                        // textAlign: TextAlign.justify,
                      ),
                    ),
                  ),
                ),

              Align(
                alignment: Alignment.topLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      color: Colors.white54,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: "Total Length: ", style: TextStyle(fontWeight: FontWeight.normal)),
                            TextSpan(
                                text: convertDistValueCoarse(
                                        Provider.of<Settings>(context, listen: false).displayUnitsDist, plan!.length)
                                    .toStringAsFixed(1)),
                            TextSpan(
                                text:
                                    unitStrDistCoarse[Provider.of<Settings>(context, listen: false).displayUnitsDist]),
                          ]),
                          style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    )
                  ],
                ),
              )
            ] +
            ((focusMode == FocusMode.addPath || focusMode == FocusMode.editPath)
                ? [
                    Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Card(
                              color: Colors.amber.shade400,
                              child: const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text.rich(
                                    TextSpan(children: [
                                      WidgetSpan(
                                          child: Icon(
                                        Icons.touch_app,
                                        size: 18,
                                        color: Colors.black,
                                      )),
                                      TextSpan(text: "Tap to add to path")
                                    ]),
                                    style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
                                  ))),
                        )),
                    Align(
                        alignment: Alignment.bottomRight,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 35,
                            icon: const Icon(
                              Icons.cancel,
                              size: 35,
                              color: Colors.red,
                            ),
                            onPressed: () {
                              // --- Cancel editing of path (don't save changes)
                              if (editingIndex != null && plan!.waypoints[editingIndex!].latlng.isEmpty) {
                                plan!.waypoints.removeAt(editingIndex!);
                              }
                              beginEditingPolyline(null);
                            },
                          ),
                          if (editablePolyline.length > 1)
                            IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 35,
                                icon: const Icon(
                                  Icons.check_circle,
                                  size: 35,
                                  color: Colors.green,
                                ),
                                onPressed: () {
                                  // --- finish editing path
                                  finishEditingPolyline();
                                })
                        ])),
                    Align(
                        alignment: Alignment.bottomLeft,
                        child: TextButton.icon(
                          icon: const Icon(
                            Icons.swap_horizontal_circle,
                            color: Colors.black,
                            size: 35,
                          ),
                          label: const Text("Reverse",
                              style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            setState(() {
                              var _temp = editablePolyline.toList();
                              editablePolyline.clear();
                              editablePolyline.addAll(_temp.reversed);
                            });
                          },
                        )),
                  ]
                : []),
      ),

      ///
      ///
      ///
      ///
      ///
      ///
      ///
      ///
      ///
      bottomNavigationBar: Container(
        constraints: const BoxConstraints(maxHeight: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // --- Add New Waypoint
                IconButton(
                    iconSize: 25,
                    icon: const ImageIcon(AssetImage("assets/images/add_waypoint_pin.png"), color: Colors.lightGreen),
                    onPressed: () {
                      setFocusMode(FocusMode.addWaypoint);
                    }),
                // --- Add New Path
                IconButton(
                    iconSize: 25,
                    icon: const ImageIcon(AssetImage("assets/images/add_waypoint_path.png"), color: Colors.yellow),
                    onPressed: () {
                      var _temp = Waypoint("", [], false, null, null);
                      editWaypoint(context, _temp, isNew: true, isPath: true)?.then((newWaypoint) {
                        if (newWaypoint != null) {
                          plan!.waypoints.add(newWaypoint);
                          beginEditingPolyline(plan!.waypoints.length - 1);
                          setFocusMode(FocusMode.addPath);
                        }
                      });
                    }),
                // --- New from Lat Lng
                IconButton(
                    iconSize: 25,
                    onPressed: () {
                      editLatLng(context).then((value) {
                        if (value != null) {
                          editWaypoint(context, Waypoint("", [value], false, null, null), isNew: true, isPath: false)
                              ?.then((newWaypoint) {
                            if (newWaypoint != null) {
                              setState(() {
                                plan!.waypoints.add(Waypoint(
                                    newWaypoint.name, newWaypoint.latlng, false, newWaypoint.icon, newWaypoint.color));
                              });
                            }
                          });
                        }
                      });
                    },
                    icon: const ImageIcon(AssetImage("assets/images/crosshair.png"))),
              ],
            ),
            Divider(
              thickness: 2,
              height: 0,
              color: Theme.of(context).backgroundColor,
            ),
            Expanded(
                child: (plan == null)
                    ? const Center(
                        child: Text("Oops, something went wrong!"),
                      )
                    :
                    // --- List of waypoints
                    ReorderableListView.builder(
                        shrinkWrap: true,
                        primary: false,
                        itemCount: plan!.waypoints.length,
                        itemBuilder: (context, i) => Slidable(
                          dragStartBehavior: DragStartBehavior.start,
                          key: ValueKey(plan!.waypoints[i]),
                          startActionPane: ActionPane(extentRatio: 0.14, motion: const ScrollMotion(), children: [
                            SlidableAction(
                              onPressed: (e) {
                                setState(() {
                                  plan!.waypoints.removeAt(i);
                                });
                              },
                              icon: Icons.delete,
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ]),
                          endActionPane: ActionPane(
                            extentRatio: 0.3,
                            motion: const ScrollMotion(),
                            children: [
                              SlidableAction(
                                onPressed: (e) {
                                  editWaypoint(
                                    context,
                                    plan!.waypoints[i],
                                  )?.then((newWaypoint) {
                                    if (newWaypoint != null) {
                                      debugPrint("Finished Editing Waypoint $i");
                                      setState(() {
                                        plan!.waypoints[i] = newWaypoint;
                                      });
                                    }
                                  });
                                },
                                icon: Icons.edit,
                                backgroundColor: Colors.grey.shade400,
                                foregroundColor: Colors.black,
                              ),
                              ReorderableDragStartListener(
                                index: i,
                                child: Container(
                                  color: Colors.grey.shade400,
                                  child: const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Icon(
                                      Icons.drag_handle,
                                      size: 24,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          child: WaypointCard(
                            waypoint: plan!.waypoints[i],
                            index: i,
                            onSelect: () {
                              debugPrint("Selected $i");

                              if (editingIndex != null) {
                                finishEditingPolyline();
                              }
                              selectedIndex = i;
                              if (plan!.waypoints[i].latlng.length > 1) {
                                beginEditingPolyline(i);
                              } else {
                                beginEditingPolyline(null);
                              }
                            },
                            onToggleOptional: () {
                              setState(() {
                                plan!.waypoints[i].isOptional = !plan!.waypoints[i].isOptional;
                                plan!.refreshLength();
                              });
                            },
                            isSelected: i == selectedIndex,
                          ),
                        ),
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex--;
                            debugPrint("WP order: $oldIndex --> $newIndex");
                            selectedIndex = null;
                            plan!.sortWaypoint(oldIndex, newIndex);
                            plan!.refreshLength();
                          });
                        },
                      )),
            // This shows when flight plan is empty
            if (plan!.waypoints.isEmpty)
              const Center(
                child: Text(
                  "Flightplan is Empty",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
