import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_map_dragmarker/dragmarker.dart';
import 'package:flutter_map_line_editor/polyeditor.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/providers/adsb.dart';

// widgets
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/map_button.dart';
import 'package:xcnav/widgets/chat_bubble.dart';
import 'package:xcnav/widgets/map_marker.dart';
import 'package:xcnav/widgets/measurement_markers.dart';
import 'package:xcnav/widgets/pilot_marker.dart';
import 'package:xcnav/widgets/waypoint_nav_bar.dart';

// dialogs
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/dialogs/tap_point.dart';

// models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/message.dart';
import 'package:xcnav/models/ga.dart';
import 'package:xcnav/models/waypoint.dart';

// misc
import 'package:xcnav/units.dart';
import 'package:xcnav/tappablePolyline.dart';

enum FocusMode {
  unlocked,
  me,
  group,
  addWaypoint,
  addPath,
  editPath,
}

class ViewMap extends StatefulWidget {
  const ViewMap({Key? key}) : super(key: key);

  @override
  State<ViewMap> createState() => ViewMapState();
}

class ViewMapState extends State<ViewMap> with AutomaticKeepAliveClientMixin<ViewMap> {
  bool mapReady = false;
  late MapController mapController;
  DateTime? lastMapChange;
  final mapKey = GlobalKey(debugLabel: "mainMap");
  double? mapAspectRatio;

  FocusMode focusMode = FocusMode.me;
  FocusMode prevFocusMode = FocusMode.me;
  bool northLock = true;

  WaypointID? editingWp;
  late PolyEditor polyEditor;

  final List<Polyline> polyLines = [];
  final List<LatLng> editablePoints = [];

  // ignore: annotate_overrides
  bool get wantKeepAlive => true;

  late PolyEditor measurementEditor;
  final measurementPolyline = Polyline(color: Colors.orange, points: [], strokeWidth: 8);

  @override
  void initState() {
    super.initState();

    // intialize the controllers
    mapController = MapController();
    mapController.onReady.then((value) => mapReady = true);

    // zoomMainMapToLatLng.stream.listen((latlng) {
    //   debugPrint("Map zoom to: $latlng");
    //   mapController.move(latlng, mapController.zoom);
    //   setFocusMode(FocusMode.unlocked);
    // });

    polyEditor = PolyEditor(
      addClosePathMarker: false,
      points: editablePoints,
      pointIcon: const Icon(
        Icons.crop_square,
        size: 20,
        color: Colors.black,
      ),
      intermediateIcon: const Icon(Icons.circle_outlined, size: 20, color: Colors.black),
      callbackRefresh: () => {setState(() {})},
    );

    measurementEditor = PolyEditor(
      addClosePathMarker: false,
      points: measurementPolyline.points,
      pointIcon: const Icon(
        Icons.crop_square,
        size: 20,
        color: Colors.black,
      ),
      intermediateIcon: const Icon(Icons.circle_outlined, size: 20, color: Colors.black),
      callbackRefresh: () => {setState(() {})},
    );
  }

  @override
  void dispose() {
    super.dispose();
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
      prevFocusMode = focusMode;
      focusMode = mode;
      if (mode != FocusMode.editPath) editingWp = null;
      if (mode == FocusMode.group) lastMapChange = null;
      debugPrint("FocusMode = $mode");
    });
    refreshMapView();
  }

  void refreshMapView() {
    Geo geo = Provider.of<MyTelemetry>(context, listen: false).geo;
    CenterZoom? centerZoom;

    // --- Orient to gps heading
    if (!northLock && (focusMode == FocusMode.me || focusMode == FocusMode.group)) {
      mapController.rotate(-geo.hdg / pi * 180);
    }
    // --- Move to center
    if (focusMode == FocusMode.me) {
      centerZoom = CenterZoom(center: LatLng(geo.lat, geo.lng), zoom: mapController.zoom);
    } else if (focusMode == FocusMode.group) {
      List<LatLng> points = Provider.of<Group>(context, listen: false).activePilots.map((e) => e.geo!.latLng).toList();
      points.add(LatLng(geo.lat, geo.lng));
      if (lastMapChange == null ||
          (lastMapChange != null && lastMapChange!.add(const Duration(seconds: 15)).isBefore(DateTime.now()))) {
        centerZoom = mapController.centerZoomFitBounds(LatLngBounds.fromPoints(points),
            options: const FitBoundsOptions(padding: EdgeInsets.all(100), maxZoom: 13, inside: false));
      } else {
        // Preserve zoom if it has been recently overriden
        centerZoom = CenterZoom(center: LatLngBounds.fromPoints(points).center, zoom: mapController.zoom);
      }
    }
    if (centerZoom != null) {
      mapController.move(centerZoom.center, centerZoom.zoom);
    }
    mapAspectRatio = mapKey.currentContext!.size!.aspectRatio;
  }

  bool markerIsInView(LatLng point) {
    if (mapReady && mapController.bounds != null && mapAspectRatio != null) {
      // transform point into north-up reference frame
      final vectorHdg = latlngCalc.bearing(mapController.center, point) + mapController.rotation;
      final vectorHypo = latlngCalc.distance(mapController.center, point);
      final transformedPoint = latlngCalc.offset(mapController.center, vectorHypo, ((vectorHdg + 180) % 360) - 180);
      final center = mapController.center;
      final theta = (((mapController.rotation.abs() % 180) - 90).abs() - 90).abs() * pi / 180;

      // super bounding box
      final bw = (mapController.bounds!.west - mapController.bounds!.east).abs();
      final bh = (mapController.bounds!.north - mapController.bounds!.south).abs();

      // solve for inscribed rectangle
      final a = mapAspectRatio!;
      final w = (a * bw) / (a * cos(theta) + sin(theta));
      final h = bh / (a * sin(theta) + cos(theta));

      // make bounding box and sample
      final fakeBounds = LatLngBounds(LatLng(center.latitude - h / 2, center.longitude - w / 2),
          LatLng(center.latitude + h / 2, center.longitude + w / 2));
      return fakeBounds.contains(transformedPoint);
    } else {
      return false;
    }
  }

  void onMapTap(BuildContext context, LatLng latlng) {
    debugPrint("onMapTap: $latlng");
    if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath) {
      // --- Add waypoint in path
      polyEditor.add(editablePoints, latlng);
    } else {
      setState(() {
        measurementPolyline.points.add(latlng);
      });
    }
  }

  void onMapLongPress(BuildContext context, LatLng latlng) {
    // Prime the editor incase we decide to make a path
    polyLines.clear();
    polyLines.add(Polyline(color: Colors.amber, points: editablePoints, strokeWidth: 5));
    editablePoints.clear();
    editablePoints.add(latlng);
    tapPointDialog(context, latlng, setFocusMode, (Waypoint newWaypoint) {
      Provider.of<ActivePlan>(context, listen: false).updateWaypoint(newWaypoint);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      color: Colors.white,
      child: Center(
        child: Stack(alignment: Alignment.center, children: [
          Consumer3<MyTelemetry, Settings, ActivePlan>(
              builder: (context, myTelemetry, settings, plan, child) => FlutterMap(
                    key: mapKey,
                    mapController: mapController,
                    options: MapOptions(
                      interactiveFlags:
                          InteractiveFlag.all & (northLock ? ~InteractiveFlag.rotate : InteractiveFlag.all),
                      center: myTelemetry.geo.latLng,
                      zoom: 12.0,
                      onTap: (tapPosition, point) => onMapTap(context, point),
                      onLongPress: (tapPosition, point) => onMapLongPress(context, point),
                      onPositionChanged: (mapPosition, hasGesture) {
                        // debugPrint("$mapPosition $hasGesture");
                        if (hasGesture && (focusMode == FocusMode.me || focusMode == FocusMode.group)) {
                          // --- Unlock any focus lock
                          setFocusMode(FocusMode.unlocked);
                        }
                      },
                      allowPanningOnScrollingParent: false,
                      plugins: [DragMarkerPlugin(), TappablePolylineMapPlugin()],
                    ),
                    layers: [
                      settings.getMapTileLayer(settings.curMapTiles),

                      // Other Pilot path trace
                      PolylineLayerOptions(
                          polylines: Provider.of<Group>(context)
                              .activePilots
                              // .toList()
                              .map((e) => e.buildFlightTrace())
                              .toList()),

                      // Flight Log
                      PolylineLayerOptions(polylines: [myTelemetry.buildFlightTrace()]),

                      // ADSB Proximity
                      if (Provider.of<ADSB>(context, listen: false).enabled)
                        CircleLayerOptions(circles: [
                          CircleMarker(
                              point: myTelemetry.geo.latLng,
                              color: Colors.transparent,
                              borderStrokeWidth: 1,
                              borderColor: Colors.black54,
                              radius: settings.proximityProfile.horizontalDist,
                              useRadiusInMeter: true)
                        ]),

                      // Next waypoint: path
                      PolylineLayerOptions(
                        polylines: plan.buildNextWpIndicator(
                            myTelemetry.geo,
                            (Provider.of<Settings>(context, listen: false).displayUnitsDist == DisplayUnitsDist.metric
                                ? 1000
                                : 1609.344)),
                      ),

                      // Waypoints: paths
                      TappablePolylineLayerOptions(
                          pointerDistanceTolerance: 30,
                          polylineCulling: true,
                          polylines: plan.waypoints.values
                              .where((value) => value.latlng.length > 1)
                              .whereNot(
                                (element) => element.id == editingWp,
                              )
                              .mapIndexed((i, e) =>
                                  TaggedPolyline(points: e.latlng, strokeWidth: 6.0, color: e.getColor(), tag: e.id))
                              .toList(),
                          onTap: (p0, tapPosition) {
                            // Select this path waypoint
                            if (plan.selectedWp == p0.tag) {
                              plan.waypoints[p0.tag]?.toggleDirection();
                            }
                            plan.selectedWp = p0.tag;
                          },
                          onLongPress: ((p0, tapPosition) {
                            // Start editing path waypoint
                            if (plan.waypoints.containsKey(p0.tag)) {
                              beginEditingLine(plan.waypoints[p0.tag]!);
                            }
                          })),

                      // Next waypoint: barbs
                      MarkerLayerOptions(
                          markers: plan
                              .buildNextWpBarbs(
                                  myTelemetry.geo,
                                  (Provider.of<Settings>(context, listen: false).displayUnitsDist ==
                                          DisplayUnitsDist.metric
                                      ? 1000
                                      : 1609.344))
                              .map((e) => Marker(
                                  point: e.latlng,
                                  width: 20,
                                  height: 20,
                                  builder: (ctx) => IgnorePointer(
                                        child: Container(
                                            transformAlignment: const Alignment(0, 0),
                                            transform: Matrix4.rotationZ(e.hdg),
                                            child:
                                                SvgPicture.asset("assets/images/chevron.svg", color: Colors.black87)),
                                      )))
                              .toList()),

                      // Waypoints: pin markers
                      DragMarkerPluginOptions(
                        markers: plan.waypoints.values
                            .map((e) => e.latlng.length == 1
                                ? DragMarker(
                                    point: e.latlng[0],
                                    height: 60 * 0.8,
                                    width: 40 * 0.8,
                                    updateMapNearEdge: true,
                                    useLongPress: true,
                                    onTap: (_) => plan.selectedWp = e.id,
                                    onLongDragEnd: (p0, p1) => {
                                          plan.moveWaypoint(e.id, [p1])
                                        },
                                    rotateMarker: true,
                                    builder: (context) => Container(
                                        transformAlignment: const Alignment(0, 0),
                                        transform: Matrix4.translationValues(0, -30 * 0.8, 0),
                                        child: MapMarker(e, 60 * 0.8)))
                                : null)
                            .whereNotNull()
                            .toList(),
                      ),

                      // Launch Location (automatic marker)
                      if (myTelemetry.launchGeo != null)
                        MarkerLayerOptions(markers: [
                          Marker(
                              width: 40 * 0.6,
                              height: 60 * 0.6,
                              point: myTelemetry.launchGeo!.latLng,
                              builder: (ctx) => Container(
                                    transformAlignment: const Alignment(0, 0),
                                    transform: Matrix4.rotationZ(-mapController.rotation * pi / 180),
                                    child: Stack(children: [
                                      Container(
                                        transform: Matrix4.translationValues(0, -60 * 0.6 / 2, 0),
                                        child: SvgPicture.asset(
                                          "assets/images/pin.svg",
                                          color: Colors.lightGreen,
                                        ),
                                      ),
                                      Center(
                                        child: Container(
                                          transform: Matrix4.translationValues(0, -60 * 0.6 / 1.5, 0),
                                          child: const Icon(
                                            Icons.flight_takeoff,
                                            size: 60 * 0.6 / 2,
                                          ),
                                        ),
                                      ),
                                    ]),
                                  ))
                        ]),

                      // GA planes (ADSB IN)
                      if (Provider.of<ADSB>(context, listen: false).enabled)
                        MarkerLayerOptions(
                            markers: Provider.of<ADSB>(context, listen: false)
                                .planes
                                .values
                                .map(
                                  (e) => Marker(
                                    width: 50.0,
                                    height: 50.0,
                                    point: e.latlng,
                                    builder: (ctx) => Container(
                                      transformAlignment: const Alignment(0, 0),
                                      transform: Matrix4.rotationZ(-mapController.rotation * pi / 180),
                                      child: Opacity(
                                        opacity: getGAtransparency(e.alt - myTelemetry.geo.alt),
                                        child: Stack(
                                          children: [
                                            /// --- GA icon
                                            Container(
                                              transformAlignment: const Alignment(0, 0),
                                              transform: Matrix4.rotationZ((mapController.rotation + e.hdg) * pi / 180),
                                              child: e.getIcon(myTelemetry.geo),
                                            ),

                                            /// --- Relative Altitude
                                            Container(
                                                transform: Matrix4.translationValues(40, 0, 0),
                                                transformAlignment: const Alignment(0, 0),
                                                child: Text.rich(
                                                  TextSpan(children: [
                                                    WidgetSpan(
                                                      child: Icon(
                                                        (e.alt - myTelemetry.geo.alt) > 0
                                                            ? Icons.keyboard_arrow_up
                                                            : Icons.keyboard_arrow_down,
                                                        color: Colors.black,
                                                        size: 21,
                                                      ),
                                                    ),
                                                    richValue(UnitType.distFine, (e.alt - myTelemetry.geo.alt).abs(),
                                                        digits: 5,
                                                        valueStyle: const TextStyle(color: Colors.black),
                                                        unitStyle:
                                                            TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                                                  ]),
                                                  overflow: TextOverflow.visible,
                                                  softWrap: false,
                                                  maxLines: 1,
                                                  style: const TextStyle(fontSize: 16),
                                                )),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList()),

                      // Live locations other pilots
                      MarkerLayerOptions(
                        markers: Provider.of<Group>(context)
                            .activePilots
                            // .toList()
                            .map((pilot) => Marker(
                                point: pilot.geo!.latLng,
                                width: 40,
                                height: 40,
                                builder: (ctx) => Container(
                                    transformAlignment: const Alignment(0, 0),
                                    transform: Matrix4.rotationZ(-mapController.rotation * pi / 180),
                                    child: PilotMarker(
                                      pilot,
                                      20,
                                      hdg: pilot.geo!.hdg + mapController.rotation * pi / 180,
                                      relAlt: pilot.geo!.alt - myTelemetry.geo.alt,
                                    ))))
                            .toList(),
                      ),

                      // "ME" Live Location Marker
                      MarkerLayerOptions(
                        markers: [
                          Marker(
                            width: 50.0,
                            height: 50.0,
                            point: myTelemetry.geo.latLng,
                            builder: (ctx) => Container(
                              transformAlignment: const Alignment(0, 0),
                              transform: Matrix4.rotationZ(myTelemetry.geo.hdg),
                              child: Image.asset("assets/images/red_arrow.png"),
                            ),
                          ),
                        ],
                      ),

                      // Measurement Polyline
                      if (focusMode != FocusMode.addPath &&
                          focusMode != FocusMode.editPath &&
                          measurementPolyline.points.isNotEmpty)
                        PolylineLayerOptions(polylines: [measurementPolyline]),
                      if (focusMode != FocusMode.addPath &&
                          focusMode != FocusMode.editPath &&
                          measurementPolyline.points.isNotEmpty)
                        DragMarkerPluginOptions(markers: measurementEditor.edit()),
                      if (focusMode != FocusMode.addPath &&
                          focusMode != FocusMode.editPath &&
                          measurementPolyline.points.isNotEmpty)
                        MarkerLayerOptions(markers: buildMeasurementMarkers(measurementPolyline.points)),

                      // Draggable line editor
                      if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath)
                        PolylineLayerOptions(polylines: polyLines),
                      if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath)
                        DragMarkerPluginOptions(markers: polyEditor.edit()),
                    ],
                  )),

          // --- Pilot Direction Markers (for when pilots are out of view)
          StreamBuilder(
              stream: mapController.mapEventStream,
              builder: (context, mapEvent) => Center(
                    child: Stack(
                        // fit: StackFit.expand,
                        children: Provider.of<Group>(context)
                            .activePilots
                            .where((e) => !markerIsInView(e.geo!.latLng))
                            .map((e) => Builder(builder: (context) {
                                  final theta = (latlngCalc.bearing(mapController.center, e.geo!.latLng) +
                                          mapController.rotation -
                                          90) *
                                      pi /
                                      180;
                                  final hypo = MediaQuery.of(context).size.width * 0.8 - 40;
                                  final dist = latlngCalc.distance(mapController.center, e.geo!.latLng);

                                  return Opacity(
                                      opacity: 0.5,
                                      child: Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          max(0, cos(theta) * hypo),
                                          max(0, sin(theta) * hypo),
                                          max(0, cos(theta) * -hypo),
                                          max(0, sin(theta) * -hypo),
                                        ),
                                        child: Stack(
                                          children: [
                                            Container(
                                                transformAlignment: const Alignment(0, 0),
                                                transform:
                                                    Matrix4.translationValues(cos(theta) * 30, sin(theta) * 30, 0)
                                                      ..rotateZ(theta),
                                                child: const Icon(
                                                  Icons.east,
                                                  color: Colors.black,
                                                  size: 40,
                                                )),
                                            Container(
                                              transformAlignment: const Alignment(0, 0),
                                              child: PilotMarker(
                                                e,
                                                20,
                                              ),
                                            ),
                                            Container(
                                                width: 40,
                                                // transformAlignment: const Alignment(0, 0),
                                                transform: Matrix4.translationValues(0, 40, 0),
                                                child: Text.rich(
                                                  richValue(UnitType.distCoarse, dist,
                                                      digits: 4,
                                                      decimals: 1,
                                                      valueStyle: const TextStyle(color: Colors.black, fontSize: 18),
                                                      unitStyle: const TextStyle(color: Colors.black87, fontSize: 14)),
                                                  softWrap: false,
                                                  textAlign: TextAlign.center,
                                                  overflow: TextOverflow.visible,
                                                ))
                                          ],
                                        ),
                                      ));
                                }))
                            .toList()),
                  )),

          // --- Chat bubbles
          Consumer<ChatMessages>(
            builder: (context, chat, child) {
              // get valid bubbles
              const numSeconds = 20;
              List<Message> bubbles = [];
              for (int i = chat.messages.length - 1; i >= 0; i--) {
                if (chat.messages[i].timestamp >
                        max(DateTime.now().millisecondsSinceEpoch - 1000 * numSeconds, chat.chatLastOpened) &&
                    chat.messages[i].pilotId != Provider.of<Profile>(context, listen: false).id) {
                  bubbles.add(chat.messages[i]);

                  Timer(const Duration(seconds: numSeconds), () {
                    // "self destruct" the message after several seconds by triggering a refresh
                    chat.refresh();
                  });
                } else {
                  break;
                }
              }
              return Positioned(
                  right: Provider.of<Settings>(context).mapControlsRightSide ? 70 : 0,
                  bottom: 80,
                  // left: 100,
                  child: Column(
                    verticalDirection: VerticalDirection.up,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: bubbles
                        .map(
                          (e) => ChatBubble(
                              false,
                              e.text,
                              AvatarRound(Provider.of<Group>(context, listen: false).pilots[e.pilotId]?.avatar, 20,
                                  tier: Provider.of<Group>(context, listen: false).pilots[e.pilotId]?.tier),
                              null,
                              e.timestamp),
                        )
                        .toList(),
                  ));
            },
          ),

          // --- Map overlay layers
          if (focusMode != FocusMode.addPath &&
              focusMode != FocusMode.editPath &&
              measurementPolyline.points.isNotEmpty)
            Positioned(
              bottom: 10,
              right: Provider.of<Settings>(context).mapControlsRightSide ? null : 10,
              left: Provider.of<Settings>(context).mapControlsRightSide ? 10 : null,
              child: IconButton(
                iconSize: 40,
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.cancel,
                  size: 40,
                  color: Colors.red,
                ),
                onPressed: () => {
                  setState(() {
                    measurementPolyline.points.clear();
                  })
                },
              ),
            ),

          if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath)
            Positioned(
              bottom: 10,
              right: Provider.of<Settings>(context).mapControlsRightSide ? null : 10,
              left: Provider.of<Settings>(context).mapControlsRightSide ? 10 : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Card(
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
                        style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                        // textAlign: TextAlign.justify,
                      ),
                    ),
                  ),
                  IconButton(
                    iconSize: 40,
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.swap_horizontal_circle,
                      size: 40,
                      color: Colors.black,
                    ),
                    onPressed: () {
                      setState(() {
                        var tmp = editablePoints.toList();
                        editablePoints.clear();
                        editablePoints.addAll(tmp.reversed);
                      });
                    },
                  ),
                  IconButton(
                    iconSize: 40,
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.cancel,
                      size: 40,
                      color: Colors.red,
                    ),
                    onPressed: () => {setFocusMode(prevFocusMode)},
                  ),
                  if (editablePoints.length > 1)
                    IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 40,
                      icon: const Icon(
                        Icons.check_circle,
                        size: 40,
                        color: Colors.green,
                      ),
                      onPressed: () {
                        // --- finish editing path
                        var plan = Provider.of<ActivePlan>(context, listen: false);
                        if (editingWp == null) {
                          var temp = Waypoint(name: "", latlngs: editablePoints.toList());
                          editWaypoint(context, temp, isNew: focusMode == FocusMode.addPath, isPath: true)
                              ?.then((newWaypoint) {
                            if (newWaypoint != null) {
                              plan.updateWaypoint(newWaypoint);
                            }
                          });
                        } else {
                          plan.moveWaypoint(editingWp!, editablePoints.toList());
                          editingWp = null;
                        }
                        setFocusMode(prevFocusMode);
                      },
                    ),
                ],
              ),
            ),

          // --- Current waypoint
          if (focusMode != FocusMode.addPath && focusMode != FocusMode.editPath)
            Positioned(
                bottom: 5,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                        child: Container(color: Colors.white30, child: const WaypointNavBar())))),

          // --- Map View Buttons
          Positioned(
            left: Provider.of<Settings>(context).mapControlsRightSide ? null : 10,
            right: Provider.of<Settings>(context).mapControlsRightSide ? 10 : null,
            top: 10,
            bottom: 10,
            child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Compass
                  MapButton(
                      size: 60,
                      onPressed: () => {
                            setState(
                              () {
                                northLock = !northLock;
                                if (northLock) mapController.rotate(0);
                              },
                            )
                          },
                      selected: false,
                      child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
                        StreamBuilder(
                            stream: mapController.mapEventStream,
                            builder: (context, event) => Container(
                                  transformAlignment: const Alignment(0, 0),
                                  transform: mapReady
                                      ? Matrix4.rotationZ(mapController.rotation * pi / 180)
                                      : Matrix4.rotationZ(0),
                                  child: northLock
                                      ? SvgPicture.asset("assets/images/compass_north.svg", fit: BoxFit.none)
                                      : SvgPicture.asset(
                                          "assets/images/compass.svg",
                                          fit: BoxFit.none,
                                        ),
                                )),
                      ])),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- Focus on Me
                      MapButton(
                        size: 60,
                        selected: focusMode == FocusMode.me,
                        child: SvgPicture.asset("assets/images/icon_controls_centermap_me.svg"),
                        onPressed: () => setFocusMode(FocusMode.me),
                      ),

                      //
                      SizedBox(
                          width: 2,
                          height: 20,
                          child: Container(
                            color: Colors.black,
                          )),
                      // --- Focus on Group
                      MapButton(
                        size: 60,
                        selected: focusMode == FocusMode.group,
                        onPressed: () => setFocusMode(FocusMode.group),
                        child: SvgPicture.asset("assets/images/icon_controls_centermap_group.svg"),
                      ),
                    ],
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    // --- Zoom In (+)
                    MapButton(
                      size: 60,
                      selected: false,
                      onPressed: () {
                        mapController.move(mapController.center, mapController.zoom + 1);
                        debugPrint("Map Zoom: ${mapController.zoom}");
                        lastMapChange = DateTime.now();
                      },
                      child: SvgPicture.asset("assets/images/icon_controls_zoom_in.svg"),
                    ),
                    //
                    SizedBox(
                        width: 2,
                        height: 20,
                        child: Container(
                          color: Colors.black,
                        )),
                    // --- Zoom Out (-)
                    MapButton(
                      size: 60,
                      selected: false,
                      onPressed: () {
                        mapController.move(mapController.center, mapController.zoom - 1);
                        debugPrint("Map Zoom: ${mapController.zoom}");
                        lastMapChange = DateTime.now();
                      },
                      child: SvgPicture.asset("assets/images/icon_controls_zoom_out.svg"),
                    ),
                  ]),
                  // --- Empty spacer to push buttons up
                  Container()
                ]),
          ),

          // --- Connection status banner (along top of map)
          if (Provider.of<Client>(context).state == ClientState.disconnected)
            const Positioned(
                top: 5,
                child: Card(
                    color: Colors.amber,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(10, 4, 10, 4),
                      child: Text.rich(
                        TextSpan(children: [
                          WidgetSpan(
                              child: Icon(
                            Icons.language,
                            size: 20,
                            color: Colors.black,
                          )),
                          TextSpan(text: "  connecting", style: TextStyle(color: Colors.black, fontSize: 20)),
                        ]),
                      ),
                    ))),
        ]),
      ),
    );
  }
}
