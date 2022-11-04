import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_map_dragmarker/dragmarker.dart';
import 'package:flutter_map_line_editor/polyeditor.dart';
import 'package:provider/provider.dart';

// --- Models
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/models/waypoint.dart';

// --- Providers
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/units.dart';

// --- Widgets
import 'package:xcnav/widgets/waypoint_card.dart';
import 'package:xcnav/widgets/make_path_barbs.dart';
import 'package:xcnav/widgets/map_marker.dart';

// --- Misc
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/views/view_map.dart';

class PlanEditor extends StatefulWidget {
  const PlanEditor({Key? key}) : super(key: key);

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  LatLngBounds? mapBounds;
  FlightPlan? plan;
  MapController mapController = MapController();
  WaypointID? editingWp;
  WaypointID? selectedWp;
  late PolyEditor polyEditor;
  final List<LatLng> editablePolyline = [];
  ScrollController scrollController = ScrollController();

  FocusMode focusMode = FocusMode.unlocked;

  String mapTileName = "topo";

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

  void setFocusMode(FocusMode mode) {
    setState(() {
      focusMode = mode;
      debugPrint("FocusMode = $mode");
    });
  }

  void beginEditingPolyline(WaypointID? waypointID) {
    setState(() {
      editingWp = waypointID;
      editablePolyline.clear();
      if (plan?.waypoints.containsKey(waypointID) == true) {
        focusMode = FocusMode.editPath;
        editablePolyline.addAll(plan!.waypoints[waypointID]!.latlng.toList());
      } else {
        focusMode = FocusMode.unlocked;
      }
    });
  }

  void finishEditingPolyline() {
    setState(() {
      if (editingWp != null && plan?.waypoints.containsKey(editingWp) == true) {
        if (editablePolyline.isNotEmpty) {
          plan!.waypoints[editingWp!]!.latlng = editablePolyline.toList();
        } else {
          plan!.waypoints.remove(editingWp!);
        }
      }
      editingWp = null;
      editablePolyline.clear();
      focusMode = FocusMode.unlocked;
      selectedWp = null;
    });
  }

  void onMapTap(BuildContext context, LatLng latlng) {
    debugPrint("onMapTap: $latlng");
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
    return WillPopScope(
      onWillPop: () {
        if (plan != null) {
          Provider.of<Plans>(context, listen: false).setPlan(plan!);
        }
        return Future.value(true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("Edit: ${plan!.name}"),
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
                      Provider.of<Settings>(context, listen: false).getMapTileLayer(mapTileName, opacity: 1.0),

                      // Flight plan markers
                      PolylineLayerOptions(
                        polylines: plan!.waypoints.values
                            // .where((value) => value.latlng.length > 1)
                            .map((e) => e.latlng.length > 1 && e.id != editingWp
                                ? Polyline(
                                    points: e.latlng, strokeWidth: e.id == selectedWp ? 8 : 4, color: e.getColor())
                                : null)
                            .whereNotNull()
                            .toList(),
                      ),

                      // Flight plan paths - directional barbs
                      MarkerLayerOptions(
                          markers: makePathBarbs(
                              editingWp != null
                                  ? plan!.waypoints.values.whereNot((e) => e.id == editingWp)
                                  // TODO: revisit
                                  // ..add(Waypoint(name: plan!.waypoints[editingWp!].name, latlngs: editablePolyline
                                  //     color: plan!.waypoints[editingWp!].color)))
                                  : plan!.waypoints.values,
                              40,
                              Provider.of<Settings>(context, listen: false).displayUnitsDist == DisplayUnitsDist.metric
                                  ? 1000
                                  : 1609.344)),

                      // Flight plan markers
                      DragMarkerPluginOptions(
                          markers: plan!.waypoints.values
                              .map((e) => e.latlng.length == 1
                                  ? DragMarker(
                                      useLongPress: true,
                                      point: e.latlng[0],
                                      height: 60 * (e.id == selectedWp ? 0.8 : 0.6),
                                      width: 40 * (e.id == selectedWp ? 0.8 : 0.6),
                                      offset: Offset(0, -30 * (e.id == selectedWp ? 0.8 : 0.6)),
                                      feedbackOffset: Offset(0, -30 * (e.id == selectedWp ? 0.8 : 0.6)),
                                      onTap: (_) => {
                                            setState(() {
                                              selectedWp = e.id;
                                              // TODO: revisit
                                              // scrollController.animateTo(60.0 * ,
                                              //     duration: const Duration(milliseconds: 100),
                                              //     curve: Curves.fastLinearToSlowEaseIn);
                                            }),
                                          },
                                      onLongDragEnd: (p0, p1) {
                                        setState(() {
                                          plan!.waypoints[e.id]?.latlng = [p1];
                                        });
                                      },
                                      builder: (context) => MapMarker(e, 60 * (e.id == selectedWp ? 0.8 : 0.6)))
                                  : null)
                              .whereNotNull()
                              .toList()),

                      // Draggable line editor
                      if (editingWp != null)
                        PolylineLayerOptions(polylines: [
                          Polyline(
                              color: plan!.waypoints[editingWp!]?.getColor() ?? Colors.black,
                              points: editablePolyline,
                              strokeWidth: 5)
                        ]),
                      if (editingWp != null) DragMarkerPluginOptions(markers: polyEditor.edit()),
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
                        child: ToggleButtons(
                          isSelected: Settings.mapTileThumbnails.keys.map((e) => e == mapTileName).toList(),
                          borderRadius: const BorderRadius.all(Radius.circular(10)),
                          borderWidth: 3,
                          borderColor: Colors.black,
                          selectedBorderColor: Colors.blue,
                          onPressed: (index) {
                            setState(() {
                              mapTileName = Settings.mapTileThumbnails.keys.toList()[index];
                            });
                          },
                          children: Settings.mapTileThumbnails.values
                              .map((e) => SizedBox(
                                    width: MediaQuery.of(context).size.width / 7,
                                    // height: 50,
                                    child: e,
                                  ))
                              .toList(),
                        ),
                      ),
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
                                if (editingWp != null && plan!.waypoints[editingWp!]!.latlng.isEmpty) {
                                  plan!.waypoints.remove(editingWp!);
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
                                var temp = editablePolyline.toList();
                                editablePolyline.clear();
                                editablePolyline.addAll(temp.reversed);
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
                        var temp = Waypoint(name: "", latlngs: []);
                        editWaypoint(context, temp, isNew: true, isPath: true)?.then((newWaypoint) {
                          if (newWaypoint != null) {
                            plan!.waypoints[newWaypoint.id] = newWaypoint;
                            beginEditingPolyline(newWaypoint.id);
                            setFocusMode(FocusMode.addPath);
                          }
                        });
                      }),
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
                      ListView.builder(
                          shrinkWrap: true,
                          primary: false,
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
                                      plan!.waypoints.remove(i);
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
                                            items[i] = newWaypoint;
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
                                  debugPrint("Selected $i");

                                  if (editingWp != null) {
                                    finishEditingPolyline();
                                  }
                                  selectedWp = items[i].id;
                                  if (items[i].latlng.length > 1) {
                                    beginEditingPolyline(items[i].id);
                                  } else {
                                    beginEditingPolyline(null);
                                  }
                                },
                                isSelected: items[i].id == selectedWp,
                              ),
                            );
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
      ),
    );
  }
}
