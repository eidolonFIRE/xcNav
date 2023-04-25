import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_line_editor/dragmarker.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';
import 'package:flutter_map_line_editor/polyeditor.dart';
import 'package:provider/provider.dart';

// --- Models
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/models/waypoint.dart';

// --- Providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/plans.dart';

// --- Widgets
import 'package:xcnav/widgets/waypoint_card.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';
import 'package:xcnav/widgets/map_selector.dart';

// --- Misc
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/views/view_map.dart';
import 'package:xcnav/tappable_polyline.dart';
import 'package:xcnav/dialogs/tap_point.dart';
import 'package:xcnav/map_service.dart';

class PlanEditor extends StatefulWidget {
  const PlanEditor({Key? key}) : super(key: key);

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  LatLngBounds? mapBounds;
  FlightPlan? plan;
  WaypointID? selectedWp;
  ScrollController scrollController = ScrollController();

  WaypointID? editingWp;
  late final PolyEditor polyEditor;

  final List<Polyline> polyLines = [];
  final List<LatLng> editablePoints = [];

  FocusMode focusMode = FocusMode.unlocked;

  MapTileSrc mapTileSrc = MapTileSrc.topo;
  double mapOpacity = 1.0;

  bool mapReady = false;
  MapController mapController = MapController();

  ValueNotifier<bool> isMapDialOpen = ValueNotifier(false);

  @override
  void initState() {
    super.initState();

    polyEditor = PolyEditor(
      addClosePathMarker: false,
      points: editablePoints,
      pointIcon: const Icon(
        Icons.crop_square,
        size: 22,
        color: Colors.black,
      ),
      intermediateIcon: const Icon(Icons.circle_outlined, size: 12, color: Colors.black),
      callbackRefresh: () => {setState(() {})},
    );
  }

  void beginEditingLine(Waypoint waypoint) {
    polyLines.clear();
    polyLines.add(Polyline(color: waypoint.getColor(), points: editablePoints, strokeWidth: 5));
    editablePoints.clear();
    editablePoints.addAll(waypoint.latlng.toList());
    editingWp = waypoint.id;
    setFocusMode(FocusMode.editPath);
  }

  void setFocusMode(FocusMode mode) {
    setState(() {
      focusMode = mode;
      debugPrint("FocusMode = $mode");
    });
  }

  void finishEditingPolyline() {
    setState(() {
      // if (editingWp != null && plan?.waypoints.containsKey(editingWp) == true) {
      //   if (editablePolyline.isNotEmpty) {
      //     plan!.waypoints[editingWp!]!.latlng = editablePolyline.toList();
      //   } else {
      //     plan!.waypoints.remove(editingWp!);
      //   }
      // }
      // editingWp = null;
      // editablePolyline.clear();
      // focusMode = FocusMode.unlocked;
      // selectedWp = null;

      // --- finish editing path
      if (editablePoints.isNotEmpty) {
        if (editingWp == null) {
          var temp = Waypoint(name: "", latlngs: editablePoints.toList());
          editWaypoint(context, temp, isNew: focusMode == FocusMode.addPath, isPath: true)?.then((newWaypoint) {
            if (newWaypoint != null) {
              plan!.waypoints[newWaypoint.id] = newWaypoint;
            }
          });
        } else {
          plan!.waypoints[editingWp]!.latlng = editablePoints.toList();
          editingWp = null;
        }
      } else {
        plan!.waypoints.remove(editingWp);
      }
      setFocusMode(FocusMode.unlocked);
    });
  }

  void onMapTap(BuildContext context, LatLng latlng) {
    isMapDialOpen.value = false;
    if (focusMode == FocusMode.addWaypoint) {
      // --- Finish adding waypoint pin
      setFocusMode(FocusMode.unlocked);
      editWaypoint(context, Waypoint(name: "", latlngs: [latlng]), isNew: true)?.then((newWaypoint) {
        if (newWaypoint != null) {
          setState(() {
            plan!.waypoints[newWaypoint.id] = (newWaypoint);
          });
        }
      });
    } else if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath) {
      // --- Add waypoint in path
      polyEditor.add(editablePoints, latlng);
    }
  }

  void onMapLongPress(BuildContext context, LatLng latlng) {
    // Prime the editor incase we decide to make a path
    polyLines.clear();
    polyLines.add(Polyline(color: Colors.amber, points: editablePoints, strokeWidth: 5));
    editablePoints.clear();
    editablePoints.add(latlng);
    tapPointDialog(context, latlng, setFocusMode, (Waypoint newWaypoint) {
      if (plan != null) {
        plan!.waypoints[newWaypoint.id] = newWaypoint;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (plan == null) {
      plan = ModalRoute.of(context)!.settings.arguments as FlightPlan;
      final center = Provider.of<MyTelemetry>(context, listen: false).geo ?? defaultGeo;
      mapBounds =
          plan!.getBounds() ?? (LatLngBounds.fromPoints([center.latlng, center.latlng..longitude += 0.05])..pad(2));
    }
    return WillPopScope(
      onWillPop: () {
        if (plan != null) {
          Provider.of<Plans>(context, listen: false).setPlan(plan!);
        }
        return Future.value(true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("Editing:  ${plan!.name}"),
        ),
        body: Container(
          color: Colors.white,
          child: Stack(
            children: [
                  FlutterMap(
                      key: const Key("planEditorMap"),
                      mapController: mapController,
                      options: MapOptions(
                        absorbPanEventsOnScrollables: false,
                        onMapReady: () {
                          setState(() {
                            mapController.fitBounds(mapBounds!);
                            mapReady = true;
                          });
                        },
                        interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                        onTap: (tapPos, latlng) => onMapTap(context, latlng),
                        onLongPress: (tapPosition, point) => onMapLongPress(context, point),
                      ),
                      children: [
                        getMapTileLayer(mapTileSrc, mapOpacity),
                        if (mapTileSrc != MapTileSrc.sectional) getMapTileLayer(MapTileSrc.airspace, 1),
                        if (mapTileSrc != MapTileSrc.sectional) getMapTileLayer(MapTileSrc.airports, 1),

                        // Flight plan markers
                        TappablePolylineLayer(
                            polylines: plan!.waypoints.values
                                .where((value) => value.isPath)
                                .whereNot((element) => element.id == editingWp)
                                .map((e) => TaggedPolyline(
                                    tag: e.id,
                                    points: e.latlng,
                                    strokeWidth: e.id == selectedWp ? 8.0 : 4.0,
                                    color: e.getColor()))
                                .toList(),
                            onTap: (p0, tapPosition) {
                              setState(() {
                                selectedWp = p0.tag;
                              });
                            },
                            onLongPress: (p0, tapPosition) {
                              if (plan!.waypoints.containsKey(p0.tag)) {
                                beginEditingLine(plan!.waypoints[p0.tag]!);
                              }
                            }),

                        // Flight plan markers
                        DragMarkers(
                            markers: plan!.waypoints.values
                                .map((e) => e.latlng.length == 1
                                    ? DragMarker(
                                        useLongPress: true,
                                        point: e.latlng[0],
                                        height: 60 * (e.id == selectedWp ? 0.8 : 0.6),
                                        width: 40 * (e.id == selectedWp ? 0.8 : 0.6),
                                        offset: Offset(0, -30 * (e.id == selectedWp ? 0.8 : 0.6)),
                                        feedbackOffset: Offset(0, -30 * (e.id == selectedWp ? 0.8 : 0.6)),
                                        onTap: (_) {
                                          setState(() {
                                            selectedWp = e.id;
                                          });
                                        },
                                        onLongDragEnd: (p0, p1) {
                                          setState(() {
                                            plan!.waypoints[e.id]?.latlng = [p1];
                                          });
                                        },
                                        builder: (context) => WaypointMarker(e, 60 * (e.id == selectedWp ? 0.8 : 0.6)))
                                    : null)
                                .whereNotNull()
                                .toList()),

                        // Draggable line editor
                        if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath)
                          PolylineLayer(polylines: polyLines),
                        if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath)
                          DragMarkers(markers: polyEditor.edit()),
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
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: SizedBox(
                            height: 40,
                            child: MapSelector(
                              isMapDialOpen: isMapDialOpen,
                              curLayer: mapTileSrc,
                              curOpacity: mapOpacity,
                              onChanged: ((layerName, opacity) {
                                setState(() {
                                  mapTileSrc = layerName;
                                  mapOpacity = opacity;
                                });
                              }),
                            )),
                      ))
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
                                        style:
                                            TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
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
                                  setState(() {
                                    // --- Cancel editing of path (don't save changes)
                                    if (editingWp != null && plan!.waypoints[editingWp!]!.latlng.isEmpty) {
                                      plan!.waypoints.remove(editingWp!);
                                    }
                                    editingWp = null;
                                    setFocusMode(FocusMode.unlocked);
                                  });
                                },
                              ),
                              if (editablePoints.length > 1)
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
                                  var temp = editablePoints.toList();
                                  editablePoints.clear();
                                  editablePoints.addAll(temp.reversed);
                                });
                              },
                            )),
                      ]
                    : []),
          ),
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
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 360, minHeight: 100),
              child: plan!.waypoints.isNotEmpty
                  ? (plan == null)
                      ? const Center(
                          child: Text("Oops, something went wrong!"),
                        )
                      :
                      // --- List of waypoints
                      ListView.builder(
                          shrinkWrap: true,
                          primary: true,
                          itemCount: plan!.waypoints.length,
                          itemBuilder: (context, i) {
                            List<Waypoint> items = plan!.waypoints.values.toList();
                            items.sort((a, b) => a.name.compareTo(b.name));
                            return Slidable(
                              dragStartBehavior: DragStartBehavior.start,
                              key: ValueKey(plan!.waypoints[i]),
                              startActionPane: ActionPane(extentRatio: 0.14, motion: const ScrollMotion(), children: [
                                SlidableAction(
                                  onPressed: (e) {
                                    setState(() {
                                      plan!.waypoints.remove(items[i].id);
                                    });
                                  },
                                  icon: Icons.delete,
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                              ]),
                              endActionPane: ActionPane(
                                extentRatio: 0.15,
                                motion: const ScrollMotion(),
                                children: [
                                  SlidableAction(
                                    onPressed: (e) {
                                      editWaypoint(
                                        context,
                                        items[i],
                                      )?.then((newWaypoint) {
                                        if (newWaypoint != null) {
                                          debugPrint("Finished Editing Waypoint $i");
                                          setState(() {
                                            plan!.waypoints[newWaypoint.id] = newWaypoint;
                                          });
                                        }
                                      });
                                    },
                                    icon: Icons.edit,
                                    backgroundColor: Colors.grey.shade400,
                                    foregroundColor: Colors.black,
                                  ),
                                ],
                              ),
                              child: WaypointCard(
                                waypoint: items[i],
                                index: i,
                                onSelect: () {
                                  setState(() {
                                    if (editingWp != null) {
                                      finishEditingPolyline();
                                    }

                                    selectedWp = items[i].id;
                                  });
                                },
                                isSelected: items[i].id == selectedWp,
                              ),
                            );
                          },
                        )
                  // This shows when flight plan is empty
                  : const Center(
                      child: Text(
                        "Flightplan is Empty",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
