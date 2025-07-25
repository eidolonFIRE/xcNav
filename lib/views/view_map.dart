import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:flutter_map_line_editor/flutter_map_line_editor.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/ble_devices/ble_device_xc170.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/weather_observation_service.dart';

// widgets
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/map_button.dart';
import 'package:xcnav/widgets/chat_bubble.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';
import 'package:xcnav/widgets/map_selector.dart';
import 'package:xcnav/widgets/measurement_markers.dart';
import 'package:xcnav/widgets/pilot_marker.dart';
import 'package:xcnav/widgets/waypoint_nav_bar.dart';

// dialogs
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/dialogs/tap_point.dart';
import 'package:xcnav/dialogs/edit_live_fuel_report.dart';

// models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/message.dart';
import 'package:xcnav/models/ga.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/models/tfr.dart';

// misc
import 'package:xcnav/units.dart';
import 'package:xcnav/main.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/datadog.dart';
import 'package:xcnav/tfr_service.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/services/ble_service.dart' as ble_service;

enum FocusMode {
  unlocked,
  me,
  group,
  addWaypoint,
  addPath,
  editPath,
  measurement,
}

class ViewMap extends StatefulWidget {
  const ViewMap({super.key});

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

  /// User is dragging something on the map layer (for less than 30 seconds)
  bool get isDragging => dragStart != null && dragStart!.isAfter(DateTime.now().subtract(const Duration(seconds: 30)));
  DateTime? dragStart;
  LatLng? draggingLatLng;

  WaypointID? editingWp;
  late PolyEditor polyEditor;

  final List<Polyline> polyLines = [];
  final List<LatLng> editablePoints = [];

  // ignore: annotate_overrides
  bool get wantKeepAlive => true;

  late PolyEditor measurementEditor;
  final List<LatLng> measurementPoints = [];

  ValueNotifier<bool> isMapDialOpen = ValueNotifier(false);
  bool hideWaypoints = false;
  bool hideWeatherObservations = false;

  DateTime? lastSavedLastKnownLatLng;

  @override
  void initState() {
    super.initState();

    // intialize the controllers
    mapController = MapController();

    // zoomMainMapToLatLng.stream.listen((latlng) {
    //   debugPrint("Map zoom to: $latlng");
    //   mapController.move(latlng, mapController.camera.zoom);
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
      callbackRefresh: (_) => {setState(() {})},
    );

    measurementEditor = PolyEditor(
      addClosePathMarker: false,
      points: measurementPoints,
      pointIcon: const Icon(
        Icons.crop_square,
        size: 20,
        color: Colors.black,
      ),
      intermediateIcon: const Icon(Icons.circle_outlined, size: 20, color: Colors.black),
      callbackRefresh: (_) => {setState(() {})},
    );

    addAttribute("view_map_focusMode", focusMode.name);
    addAttribute("view_map_northLockMap", settingsMgr.northlockMap.value);
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
      if (focusMode == FocusMode.unlocked || focusMode == FocusMode.me || focusMode == FocusMode.group) {
        prevFocusMode = focusMode;
      }
      focusMode = mode;
      if (mode != FocusMode.editPath) editingWp = null;
      if (mode == FocusMode.group) lastMapChange = null;
      debugPrint("FocusMode = $mode");

      addAttribute("view_map_focusMode", mode.name);
    });
    refreshMapView();
  }

  void refreshMapView() {
    Geo? geo = Provider.of<MyTelemetry>(context, listen: false).geo;

    if (geo != null) {
      LatLng? center;
      double zoom = mapController.camera.zoom;

      // --- Orient to gps heading
      if (!settingsMgr.northlockMap.value && (focusMode == FocusMode.me || focusMode == FocusMode.group)) {
        mapController.rotate(-geo.hdg / pi * 180);
      }
      // --- Move to center
      if (focusMode == FocusMode.me) {
        center = geo.latlng;
      } else if (focusMode == FocusMode.group) {
        List<LatLng> points =
            Provider.of<Group>(context, listen: false).activePilots.map((e) => e.geo!.latlng).toList();
        points.add(LatLng(geo.lat, geo.lng));
        if (settingsMgr.groupViewWaypoint.value) {
          // Add selected waypoint into view
          points.addAll(Provider.of<ActivePlan>(context, listen: false).getSelectedWp()?.latlng ?? []);
        }
        if (lastMapChange == null ||
            (lastMapChange != null && lastMapChange!.add(const Duration(seconds: 15)).isBefore(DateTime.now()))) {
          final camFit =
              CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(100), maxZoom: 13)
                  .fit(mapController.camera);
          center = camFit.center;
          zoom = camFit.zoom;
        } else {
          // Preserve zoom if it has been recently overriden

          center = LatLngBounds.fromPoints(points).center;
        }
      }
      if (center != null) {
        mapController.move(center, zoom);
      }
      mapAspectRatio = mapKey.currentContext!.size!.aspectRatio;
    }
  }

  bool markerIsInView(LatLng point) {
    if (mapReady && mapAspectRatio != null) {
      // transform point into north-up reference frame
      final vectorHdg = latlngCalc.bearing(mapController.camera.center, point) + mapController.camera.rotation;
      final vectorHypo = latlngCalc.distance(mapController.camera.center, point);
      final transformedPoint =
          latlngCalc.offset(mapController.camera.center, vectorHypo, ((vectorHdg + 180) % 360) - 180);
      final center = mapController.camera.center;
      final theta = (((mapController.camera.rotation.abs() % 180) - 90).abs() - 90).abs() * pi / 180;

      // super bounding box
      final bw = (mapController.camera.visibleBounds.west - mapController.camera.visibleBounds.east).abs();
      final bh = (mapController.camera.visibleBounds.north - mapController.camera.visibleBounds.south).abs();

      // solve for inscribed rectangle
      final a = mapAspectRatio!;
      final w = (a * bw) / (a * cos(theta) + sin(theta));
      final h = bh / (a * sin(theta) + cos(theta));

      // make bounding box and sample
      final fakeBounds = LatLngBounds(clampLatLng(center.latitude - h / 2, center.longitude - w / 2),
          clampLatLng(center.latitude + h / 2, center.longitude + w / 2));
      return fakeBounds.contains(transformedPoint);
    } else {
      return false;
    }
  }

  void onMapTap(BuildContext context, LatLng latlng) {
    debugPrint("onMapTap: $latlng");
    isMapDialOpen.value = false;
    final plan = Provider.of<ActivePlan>(context, listen: false);
    if (editingWp != null && plan.waypoints.containsKey(editingWp) && plan.waypoints[editingWp]!.latlng.length == 1) {
      setState(() {
        editingWp = null;
      });
    }
    if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath) {
      // Add waypoint in path
      polyEditor.add(editablePoints, latlng);
    } else if (focusMode == FocusMode.measurement) {
      // Add point to measurement
      measurementEditor.add(measurementPoints, latlng);
    } else {
      // check tap on TFR
      for (final tfr in getLoadedTFRs() ?? <TFR>[]) {
        if (tfr.containsPoint(latlng)) {
          // Tap on TFR
          tfr.showInfoDialog(context);
          break;
        }
      }
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

    debugPrint("Build view_map");

    // Hookup the measurement points to the active plan provider.
    Provider.of<ActivePlan>(context, listen: false).mapMeasurement = measurementPoints;

    final LayerHitNotifier<String> polylineHit = ValueNotifier(null);

    settingsMgr.mapControlsRightSide.listenable.addListener(() => setState(() {}));

    return Container(
      color: Colors.white,
      child: Stack(alignment: Alignment.center, children: [
        // NOTE: MyTelemetry is not part of this consumer because refreshMapView is already called elsewhere on MyTelemetry changes
        Consumer<ActivePlan>(
            builder: (context, plan, child) => FlutterMap(
                  key: mapKey,
                  mapController: mapController,
                  options: MapOptions(
                    onMapReady: () {
                      setState(() {
                        mapReady = true;
                      });
                    },
                    interactionOptions: InteractionOptions(
                        flags: InteractiveFlag.all &
                            (settingsMgr.northlockMap.value ? ~InteractiveFlag.rotate : InteractiveFlag.all)),
                    initialCenter: Provider.of<MyTelemetry>(context, listen: false).geo?.latlng ?? lastKnownLatLng,
                    initialZoom: 12.0,
                    minZoom: 2,
                    onTap: (tapPosition, point) {
                      // WORKAROUND - calculate relative offset ourselves
                      final widgetBox = mapKey.currentContext?.findRenderObject() as RenderBox?;
                      if (widgetBox != null) {
                        final relativeTapPos = tapPosition.global - widgetBox.localToGlobal(Offset.zero);
                        final correctedLatLng = mapController.camera.offsetToCrs(relativeTapPos);
                        // outgoing call...
                        onMapTap(context, correctedLatLng);
                      }
                    },
                    onLongPress: (tapPosition, point) {
                      // WORKAROUND - calculate relative offset ourselves
                      final widgetBox = mapKey.currentContext?.findRenderObject() as RenderBox?;
                      if (widgetBox != null) {
                        final relativeTapPos = tapPosition.global - widgetBox.localToGlobal(Offset.zero);
                        final correctedLatLng = mapController.camera.offsetToCrs(relativeTapPos);
                        // outgoing call...
                        onMapLongPress(context, correctedLatLng);
                      }
                    },
                    onPositionChanged: (mapPosition, hasGesture) {
                      if (lastSavedLastKnownLatLng == null ||
                          lastSavedLastKnownLatLng!.difference(DateTime.now()).abs() > const Duration(minutes: 2)) {
                        lastSavedLastKnownLatLng = DateTime.now();
                        SharedPreferences.getInstance().then((prefs) {
                          prefs.setString("lastKnownLatLng",
                              jsonEncode({"lat": mapPosition.center.latitude, "lng": mapPosition.center.longitude}));
                        });
                      }

                      if (hasGesture) {
                        isMapDialOpen.value = false;
                        if (focusMode == FocusMode.me || focusMode == FocusMode.group) {
                          // --- Unlock any focus lock
                          setFocusMode(FocusMode.unlocked);
                        }
                      }
                    },
                  ),
                  children: [
                    Opacity(
                        opacity: settingsMgr.mainMapOpacity.value,
                        child: getMapTileLayer(settingsMgr.mainMapTileSrc.value)),

                    // TFRs
                    FutureBuilder<List<TFR>?>(
                        future:
                            getTFRs(Provider.of<MyTelemetry>(context, listen: false).geo?.latlng ?? lastKnownLatLng),
                        builder: (context, tfrsFuture) {
                          if (tfrsFuture.hasData) {
                            List<Polygon> polygons = [];

                            for (final eachTfr in tfrsFuture.data!) {
                              for (final shape in eachTfr.shapes) {
                                final color = eachTfr.isActive(const Duration(hours: 3)) ? Colors.red : Colors.orange;
                                polygons.add(Polygon(
                                    points: shape,
                                    color: color.withAlpha(50),
                                    borderColor: color,
                                    borderStrokeWidth: 4));
                              }
                            }

                            return PolygonLayer(
                              polygons: polygons,
                            );
                          } else {
                            return Container();
                          }
                        }),

                    // https://nowcoast.noaa.gov/help/#!section=map-service-list
                    // if (localeZone == "NA" && settingsMgr.showWeatherOverlay.value)
                    //   Opacity(
                    //     opacity: min(1.0, max(0.2, (14.0 - (mapReady ? mapController.camera.zoom : 0)) / 10.0)),
                    //     child: TileLayer(
                    //         backgroundColor: Colors.transparent,
                    //         wmsOptions: WMSTileLayerOptions(
                    //           layers: ["1"],
                    //           baseUrl:
                    //               "https://nowcoast.noaa.gov/arcgis/services/nowcoast/radar_meteo_imagery_nexrad_time/MapServer/WMSServer?",
                    //         )),
                    //   ),

                    // Other Pilot path trace
                    if (Provider.of<Group>(context).activePilots.isNotEmpty)
                      PolylineLayer(
                          polylines: Provider.of<Group>(context)
                              .activePilots
                              // .toList()
                              .map((e) => e.buildFlightTrace())
                              .toList()),

                    // Flight Log
                    if (Provider.of<MyTelemetry>(context, listen: false).flightTrace.isNotEmpty)
                      PolylineLayer(polylines: [Provider.of<MyTelemetry>(context, listen: false).buildFlightTrace()]),

                    // ADSB Proximity
                    if (Provider.of<ADSB>(context, listen: false).enabled &&
                        Provider.of<MyTelemetry>(context, listen: false).geo != null)
                      CircleLayer(circles: [
                        CircleMarker(
                            point: Provider.of<MyTelemetry>(context, listen: false).geo!.latlng,
                            color: Colors.transparent,
                            borderStrokeWidth: 1,
                            borderColor: Colors.black54,
                            radius: proximityProfileOptions[settingsMgr.adsbProximitySize.value]!.horizontalDist,
                            useRadiusInMeter: true)
                      ]),

                    // Next waypoint: path
                    if (Provider.of<MyTelemetry>(context, listen: false).geo != null && plan.selectedWp != null)
                      PolylineLayer(
                        polylines: plan.buildNextWpIndicator(Provider.of<MyTelemetry>(context, listen: true).geo!,
                            (settingsMgr.displayUnitDist.value == DisplayUnitsDist.metric ? 1000 : 1609.344),
                            baseTiles: settingsMgr.mainMapTileSrc.value),
                      ),

                    // Waypoints: paths
                    if (!hideWaypoints)
                      GestureDetector(
                        onTapDown: (details) {
                          if (focusMode == FocusMode.measurement) {
                            measurementEditor.add(
                                measurementPoints, mapController.camera.offsetToCrs(details.localPosition));
                          }
                        },
                        onTap: () {
                          if (focusMode != FocusMode.measurement) {
                            final p0 = polylineHit.value?.hitValues.first;
                            if (p0 != null) {
                              final wp = plan.waypoints[p0];
                              if (wp != null) {
                                // Select this path waypoint
                                if (focusMode != FocusMode.measurement) {
                                  if (plan.selectedWp == p0) {
                                    wp.toggleDirection();
                                  }
                                  plan.selectedWp = p0;
                                }
                              }
                            }
                          }
                        },
                        onLongPress: (() {
                          // Start editing path waypoint
                          final p0 = polylineHit.value?.hitValues.first;
                          if (p0 != null && focusMode != FocusMode.measurement) {
                            if (plan.waypoints.containsKey(p0)) {
                              beginEditingLine(plan.waypoints[p0]!);
                            }
                          }
                        }),
                        child: PolylineLayer(
                          hitNotifier: polylineHit,
                          minimumHitbox: 30,
                          polylines: plan.waypoints.values
                              .where((value) => value.latlng.length > 1)
                              .whereNot(
                                (element) => element.id == editingWp,
                              )
                              .map((e) =>
                                  Polyline(points: e.latlng, strokeWidth: 6.0, color: e.getColor(), hitValue: e.id))
                              .toList(),
                        ),
                      ),

                    // Next waypoint: barbs
                    if (Provider.of<MyTelemetry>(context, listen: false).geo != null)
                      MarkerLayer(
                          markers: plan
                              .buildNextWpBarbs(Provider.of<MyTelemetry>(context, listen: true).geo!,
                                  (settingsMgr.displayUnitDist.value == DisplayUnitsDist.metric ? 1000 : 1609.344))
                              .map((e) => Marker(
                                  point: e.latlng,
                                  width: 20,
                                  height: 20,
                                  child: IgnorePointer(
                                    child: Container(
                                        transformAlignment: const Alignment(0, 0),
                                        transform: Matrix4.rotationZ(e.hdg),
                                        child: SvgPicture.asset("assets/images/chevron.svg",
                                            colorFilter: const ColorFilter.mode(Colors.black87, BlendMode.srcIn))),
                                  )))
                              .toList()),

                    // Measurement: yellow line
                    if (focusMode == FocusMode.measurement && measurementPoints.isNotEmpty)
                      PolylineLayer(
                          polylines: [Polyline(points: measurementPoints, color: Colors.orange, strokeWidth: 8)]),

                    // (DEBUG): check the tiles being loaded
                    // if (mapReady)
                    //   PolygonLayer(
                    //       polygons: WeatherObservationService.iterTiles(mapController.camera.visibleBounds)
                    //           .map((e) => Polygon(
                    //               points: tileToLatLngs(e),
                    //               color: Color.fromARGB(
                    //                   100, (e.x * 30) % 255, (e.y * 30) % 255, (e.x * 30 + e.y * 20) % 255)))
                    //           .toList()),

                    // WeatherObservations
                    if (mapReady && !hideWeatherObservations && mapController.camera.zoom > 7)
                      MarkerLayer(
                          markers: getWeatherObservations(mapController.camera.visibleBounds)
                              .map((e) => Marker(
                                    height: 28,
                                    width: 100,
                                    point: e.latlng,
                                    rotate: true,
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      transform: Matrix4.translationValues(-14, 0, 0),
                                      child: Row(
                                        // mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IgnorePointer(
                                            child: ClipRRect(
                                              borderRadius: const BorderRadius.all(Radius.circular(10)),
                                              child: Container(
                                                color: e.color,
                                                child:
                                                    // space for arrow
                                                    Padding(
                                                  padding: const EdgeInsets.only(left: 28, right: 8),
                                                  child: Text.rich(
                                                    TextSpan(children: [
                                                      TextSpan(
                                                          text: printValue(UnitType.speed, e.windSpd!,
                                                              digits: 2, decimals: 0)!),
                                                      TextSpan(
                                                          text: (e.windGust != null
                                                              ? " g${printValue(UnitType.speed, e.windGust!, digits: 2, decimals: 0)}"
                                                              : ''),
                                                          style: const TextStyle(fontSize: 13))
                                                    ]),
                                                    maxLines: 1,
                                                    softWrap: false,
                                                    overflow: TextOverflow.visible,
                                                    style: const TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 18,
                                                        overflow: TextOverflow.visible),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ))
                              .toList()),

                    if (mapReady && !hideWeatherObservations && mapController.camera.zoom > 7)
                      MarkerLayer(
                          markers: getWeatherObservations(mapController.camera.visibleBounds)
                              .map(
                                (e) => Marker(
                                  width: 14.0,
                                  height: 14.0,
                                  point: e.latlng,
                                  rotate: false,
                                  alignment: Alignment.center,
                                  child: IgnorePointer(
                                    child: (e.windDir == null || (e.windSpd ?? 0) < 0.01)
                                        ? Padding(
                                            padding: const EdgeInsets.all(2),
                                            child: Container(
                                                decoration: const BoxDecoration(
                                              color: Colors.black,
                                              shape: BoxShape.circle,
                                            )),
                                          )
                                        : Container(
                                            transformAlignment: const Alignment(0, 0),
                                            transform: Matrix4.rotationZ((e.windDir ?? 0) * pi / 180),
                                            child: SvgPicture.asset("assets/images/simple_arrow.svg",
                                                colorFilter: const ColorFilter.mode(Colors.black87, BlendMode.srcIn))),
                                  ),
                                ),
                              )
                              .toList()),

                    // Waypoint markers
                    if (!hideWaypoints)
                      MarkerLayer(
                        markers: plan.waypoints.values
                            .where((e) => e.latlng.length == 1 && e.id != editingWp)
                            .map((e) => Marker(
                                point: e.latlng[0],
                                height: 60 * 0.8,
                                width: 40 * 0.8,
                                rotate: true,
                                alignment: Alignment.topCenter,
                                child: GestureDetector(
                                  onTap: () {
                                    if (focusMode == FocusMode.measurement) {
                                      measurementEditor.add(measurementPoints, e.latlng.first);
                                    } else {
                                      plan.selectedWp = e.id;
                                    }
                                  },
                                  onLongPress: () {
                                    if (!e.ephemeral) {
                                      setState(() {
                                        editingWp = e.id;
                                        draggingLatLng = null;
                                      });
                                    }
                                  },
                                  child: WaypointMarker(e, 60 * 0.8),
                                )))
                            .toList(),
                      ),

                    // --- Draggable waypoints
                    if (editingWp != null &&
                        plan.waypoints.containsKey(editingWp) &&
                        plan.waypoints[editingWp]!.latlng.length == 1)
                      DragMarkers(markers: [
                        DragMarker(
                            point: draggingLatLng ?? plan.waypoints[editingWp]!.latlng.first,
                            size: const Size(60 * 0.8, 60 * 0.8),
                            onTap: (_) => plan.selectedWp = editingWp,
                            onDragEnd: (p0, p1) {
                              plan.moveWaypoint(editingWp!, [p1]);
                              dragStart = null;
                            },
                            onDragUpdate: (_, p1) {
                              draggingLatLng = p1;
                            },
                            onDragStart: (p0, p1) {
                              setState(() {
                                draggingLatLng = p1;
                                dragStart = DateTime.now();
                              });
                            },
                            rotateMarker: true,
                            builder: (context, latlng, isDragging) {
                              if (editingWp != null &&
                                  plan.waypoints.containsKey(editingWp) &&
                                  plan.waypoints[editingWp]!.latlng.length == 1) {
                                return Stack(
                                  children: [
                                    Container(
                                        transformAlignment: const Alignment(0, 0),
                                        transform: Matrix4.translationValues(0, -30 * 0.8, 0),
                                        child: WaypointMarker(plan.waypoints[editingWp]!, 60 * 0.8)),
                                    Container(
                                        transformAlignment: const Alignment(0, 0),
                                        transform: Matrix4.translationValues(12, 25, 0),
                                        child: const Icon(
                                          Icons.open_with,
                                          color: Colors.black,
                                        )),
                                  ],
                                );
                              } else {
                                // editingWp must've been removed while being drug.
                                setState(() {
                                  editingWp = null;
                                });
                                return Container();
                              }
                            })
                      ]),

                    // --- draggable waypoint mode buttons
                    if (editingWp != null &&
                        plan.waypoints.containsKey(editingWp) &&
                        !plan.waypoints[editingWp]!.isPath)
                      MarkerLayer(
                        markers: [
                          Marker(
                              rotate: true,
                              height: 240,
                              point: plan.waypoints[editingWp]!.latlng.first,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: 140,
                                  ),
                                  FloatingActionButton.small(
                                    heroTag: "editWaypoint",
                                    backgroundColor: Colors.lightBlue,
                                    onPressed: () {
                                      editWaypoint(context, plan.waypoints[editingWp]!,
                                              isNew: focusMode == FocusMode.addPath,
                                              isPath: plan.waypoints[editingWp]!.isPath)
                                          ?.then((newWaypoint) {
                                        if (newWaypoint != null) {
                                          plan.updateWaypoint(newWaypoint);
                                        }
                                      });
                                      editingWp = null;
                                    },
                                    child: const Icon(Icons.edit),
                                  ),
                                  FloatingActionButton.small(
                                    heroTag: "deleteWaypoint",
                                    backgroundColor: Colors.red,
                                    onPressed: () {
                                      setState(() {
                                        plan.removeWaypoint(editingWp!);
                                        editingWp = null;
                                      });
                                    },
                                    child: const Icon(Icons.delete),
                                  ),
                                ],
                              ))
                        ],
                      ),

                    // GA planes (ADSB IN)
                    if (Provider.of<ADSB>(context, listen: false).enabled)
                      MarkerLayer(
                          markers: Provider.of<ADSB>(context, listen: false)
                              .planes
                              .values
                              .map(
                                (e) => Marker(
                                  width: 50.0,
                                  height: 50.0,
                                  point: e.latlng,
                                  child: Container(
                                    transformAlignment: const Alignment(0, 0),
                                    transform: Matrix4.rotationZ(-mapController.camera.rotation * pi / 180),
                                    child: Opacity(
                                      opacity: getGAtransparency(
                                          e.alt - (Provider.of<MyTelemetry>(context, listen: false).geo?.alt ?? 0)),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          /// --- GA icon
                                          Container(
                                            transformAlignment: const Alignment(0, 0),
                                            transform:
                                                Matrix4.rotationZ((mapController.camera.rotation + e.hdg) * pi / 180),
                                            child: e.getIcon(),
                                          ),

                                          Container(
                                            transform: Matrix4.translationValues(50, 20, 0),
                                            transformAlignment: const Alignment(0, 0),
                                            child: Text(
                                              e.id,
                                              maxLines: 1,
                                              style: const TextStyle(
                                                  color: Colors.black, fontSize: 11, overflow: TextOverflow.visible),
                                            ),
                                          ),

                                          /// --- Relative Altitude
                                          if (Provider.of<MyTelemetry>(context, listen: false).geo != null)
                                            Container(
                                                transform: Matrix4.translationValues(40, 0, 0),
                                                transformAlignment: const Alignment(0, 0),
                                                child: Text.rich(
                                                  TextSpan(children: [
                                                    WidgetSpan(
                                                      child: Icon(
                                                        (e.alt -
                                                                    Provider.of<MyTelemetry>(context, listen: false)
                                                                        .geo!
                                                                        .alt) >
                                                                0
                                                            ? Icons.keyboard_arrow_up
                                                            : Icons.keyboard_arrow_down,
                                                        color: Colors.black,
                                                        size: 21,
                                                      ),
                                                    ),
                                                    richValue(
                                                        UnitType.distFine,
                                                        (e.alt -
                                                                Provider.of<MyTelemetry>(context, listen: false)
                                                                    .geo!
                                                                    .alt)
                                                            .abs(),
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
                    MarkerLayer(
                      markers: Provider.of<Group>(context)
                          .activePilots
                          // .toList()
                          .map((pilot) => Marker(
                              point: pilot.geo!.latlng,
                              width: 40,
                              height: 40,
                              child: Container(
                                  transformAlignment: const Alignment(0, 0),
                                  transform: Matrix4.rotationZ(-mapController.camera.rotation * pi / 180),
                                  child: PilotMarker(
                                    pilot,
                                    20,
                                    hdg: pilot.geo!.hdg + mapController.camera.rotation * pi / 180,
                                    relAlt: pilot.geo!.alt - Provider.of<MyTelemetry>(context, listen: false).geo!.alt,
                                  ))))
                          .toList(),
                    ),

                    // Fuel Warning
                    Consumer2<MyTelemetry, ActivePlan>(builder: (context, myTelemetry, activePlan, _) {
                      if (myTelemetry.sumFuelStat != null && myTelemetry.geo != null && activePlan.selectedWp != null) {
                        final waypointETA = activePlan.getSelectedWp()!.eta(myTelemetry.geo!, 1);
                        final enduranceDist = myTelemetry.speedSmooth.value *
                            myTelemetry.sumFuelStat!
                                .extrapolateEndurance(myTelemetry.fuelReports.last, from: clock.now())
                                .inSeconds;

                        if (waypointETA.distance >= enduranceDist && enduranceDist >= 0) {
                          final fuelIntercept = activePlan.getSelectedWp()!.interpolate(
                              enduranceDist, waypointETA.pathIntercept?.index ?? 0,
                              initialLatlng: myTelemetry.geo!.latlng);

                          return MarkerLayer(
                            markers: [
                              Marker(
                                width: 50,
                                height: 50,
                                point: fuelIntercept.latlng,
                                child: const Stack(
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.only(top: 10),
                                      child: Center(
                                        child: Icon(
                                          Icons.circle,
                                          size: 30,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.warning_rounded,
                                      size: 50,
                                      color: Colors.black,
                                    ),
                                    Center(
                                      child: Padding(
                                        padding: EdgeInsets.only(top: 11, left: 3),
                                        child: Icon(
                                          Icons.local_gas_station,
                                          size: 25,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            ],
                          );
                        } else {
                          return Container();
                        }
                      } else {
                        return Container();
                      }
                    }),

                    // "ME" Live Location Marker
                    Consumer<MyTelemetry>(builder: (context, myTelemetry, _) {
                      if (myTelemetry.geo != null) {
                        return MarkerLayer(
                          markers: [
                            Marker(
                              width: 50.0,
                              height: 50.0,
                              point: myTelemetry.geo!.latlng,
                              child: Container(
                                transformAlignment: const Alignment(0, 0),
                                transform: Matrix4.rotationZ(myTelemetry.geo!.hdg),
                                child: Image.asset("assets/images/red_arrow.png"),
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Container();
                      }
                    }),

                    // Measurement Polyline
                    if (focusMode == FocusMode.measurement && measurementPoints.isNotEmpty)
                      DragMarkers(markers: measurementEditor.edit()),
                    if (focusMode == FocusMode.measurement && measurementPoints.isNotEmpty)
                      MarkerLayer(markers: buildMeasurementMarkers(measurementPoints)),

                    // Draggable line editor
                    if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath)
                      PolylineLayer(polylines: polyLines),
                    if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath)
                      DragMarkers(markers: polyEditor.edit()),
                  ],
                )),

        // --- Pilot Direction Markers (for when pilots are out of view)
        StreamBuilder(
            stream: mapController.mapEventStream,
            builder: (context, mapEvent) => SizedBox(
                  width: min(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
                  height: min(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
                  child: Stack(
                      alignment: Alignment.center,
                      children: Provider.of<Group>(context)
                          .activePilots
                          .where((e) => !markerIsInView(e.geo!.latlng))
                          .map((e) => Builder(builder: (context) {
                                final theta = (latlngCalc.bearing(mapController.camera.center, e.geo!.latlng) +
                                        mapController.camera.rotation -
                                        90) *
                                    pi /
                                    180;
                                final hypo = MediaQuery.of(context).size.width * 0.8 - 40;
                                final dist = latlngCalc.distance(mapController.camera.center, e.geo!.latlng);

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
                                              transform: Matrix4.translationValues(cos(theta) * 30, sin(theta) * 30, 0)
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

        ///////////////////////////////////////////////////////////////////////////////////////////
        // --- Secondary column (default to right side)
        Positioned(
          left: settingsMgr.mapControlsRightSide.value ? 10 : null,
          right: settingsMgr.mapControlsRightSide.value ? null : 10,
          top: 10,
          bottom: 10,
          child: LayoutBuilder(builder: (context, constaints) {
            final buttonSize = max(30, min(60, constaints.maxHeight / 8)).toDouble();
            return Align(
              alignment: Alignment.bottomRight,
              child: Column(
                verticalDirection: VerticalDirection.up,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment:
                    settingsMgr.mapControlsRightSide.value ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                // crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- fuel button
                  Align(
                      alignment: Alignment.bottomRight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        verticalDirection: VerticalDirection.up,
                        children: [
                          MapButton(
                            size: buttonSize,
                            selected: false,
                            child: const Icon(Icons.local_gas_station, color: Colors.black, size: 30),
                            onPressed: () => {editLiveFuelReport(context)},
                          ),
                          SizedBox(
                              width: 2,
                              height: buttonSize / 6,
                              child: Container(
                                color: Colors.black,
                              )),
                          // --- Fuel remaining info
                          Consumer<MyTelemetry>(builder: (context, myTelemetry, _) {
                            return Container(
                              foregroundDecoration: BoxDecoration(
                                  border: Border.all(width: 0.5, color: Colors.black),
                                  borderRadius: const BorderRadius.all(Radius.circular(15))),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                                      child: Container(
                                          color: Colors.white38,
                                          child: Builder(builder: (context) {
                                            final fuelReport = myTelemetry.fuelReports.lastOrNull;

                                            if (fuelReport != null) {
                                              if (myTelemetry.sumFuelStat == null || !myTelemetry.inFlight) {
                                                final warn = fuelReport.amount <= 1;
                                                final style = TextStyle(
                                                    color: warn ? Colors.red : Colors.black,
                                                    fontSize: 20,
                                                    fontWeight: warn ? FontWeight.bold : FontWeight.normal);
                                                return Padding(
                                                    padding: const EdgeInsets.all(8.0),
                                                    child: Text.rich(richValue(UnitType.fuel, fuelReport.amount,
                                                        decimals: 1, autoDecimalThresh: 2, valueStyle: style)));
                                              } else {
                                                final etaEmpty = myTelemetry.sumFuelStat!
                                                    .extrapolateEndurance(fuelReport, from: clock.now());

                                                final warn = etaEmpty < const Duration(minutes: 15);
                                                final style = TextStyle(
                                                    color: warn ? Colors.red : Colors.black,
                                                    fontSize: 20,
                                                    fontWeight: warn ? FontWeight.bold : FontWeight.normal);
                                                return Padding(
                                                    padding: const EdgeInsets.all(8.0),
                                                    child: Text.rich(richHrMin(duration: etaEmpty, valueStyle: style)));
                                              }
                                            } else {
                                              return const Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: Text(
                                                  "?",
                                                  style: TextStyle(color: Colors.black, fontSize: 20),
                                                ),
                                              );
                                            }
                                          })))),
                            );
                          }),

                          // BLE xc170
                          if (ble_service.bleDeviceXc170.device != null)
                            Container(
                                foregroundDecoration: BoxDecoration(
                                    border: Border.all(width: 0.5, color: Colors.black),
                                    borderRadius: const BorderRadius.all(Radius.circular(15))),
                                child: ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                                        child: Container(
                                            color: Colors.white38,
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: StreamBuilder(
                                                  stream: ble_service.bleDeviceXc170.device?.connectionState,
                                                  builder: (context, state) {
                                                    return StreamBuilder(
                                                        stream: ble_service.bleDeviceXc170.fuelSensorRawStream,
                                                        builder: (context, value) => Text.rich(TextSpan(children: [
                                                              WidgetSpan(
                                                                  child: Icon(
                                                                state.data == BluetoothConnectionState.connected
                                                                    ? Icons.bluetooth_connected
                                                                    : Icons.bluetooth_disabled,
                                                                size: 30,
                                                                color: state.data == BluetoothConnectionState.connected
                                                                    ? Colors.blue
                                                                    : Colors.grey.shade800,
                                                              )),
                                                              if (value.data?.status == ValueInRange.aboveRange)
                                                                TextSpan(
                                                                    text: ">",
                                                                    style:
                                                                        TextStyle(fontSize: 30, color: Colors.green)),
                                                              if (value.data?.status == ValueInRange.belowRange)
                                                                TextSpan(
                                                                    text: "<",
                                                                    style: TextStyle(fontSize: 30, color: Colors.red)),
                                                              richValue(UnitType.fuel, value.data?.value ?? 0,
                                                                  digits: 2,
                                                                  decimals: 1,
                                                                  valueStyle: const TextStyle(
                                                                      color: Colors.black, fontSize: 30),
                                                                  unitStyle: TextStyle(
                                                                      color: Colors.grey.shade700, fontSize: 20)),
                                                            ])));
                                                  }),
                                            ))))),
                        ],
                      )),

                  if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Card(
                            color: Colors.amber.shade400,
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text.rich(
                                TextSpan(children: [
                                  WidgetSpan(
                                      child: Icon(
                                    Icons.touch_app,
                                    size: 18,
                                    color: Colors.black,
                                  )),
                                  TextSpan(text: "Tap to add to path".tr())
                                ]),
                                style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: CircleAvatar(
                              backgroundColor: Colors.white,
                              maxRadius: 20,
                              child: IconButton(
                                iconSize: 40,
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.cancel,
                                  size: 40,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  measurementPoints.clear();
                                  setFocusMode(prevFocusMode);
                                },
                              ),
                            ),
                          ),
                          if (editablePoints.length > 1 && focusMode != FocusMode.measurement)
                            CircleAvatar(
                              backgroundColor: Colors.white,
                              maxRadius: 20,
                              child: IconButton(
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
                            ),
                        ],
                      ),
                    ),

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
                      return Column(
                        verticalDirection: VerticalDirection.up,
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment:
                            settingsMgr.mapControlsRightSide.value ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                        children: bubbles
                            .map(
                              (e) => ChatBubble(
                                false,
                                !settingsMgr.mapControlsRightSide.value,
                                e.text,
                                AvatarRound(Provider.of<Group>(context, listen: false).pilots[e.pilotId]?.avatar, 20),
                                null,
                                e.timestamp,
                                maxWidth: MediaQuery.of(context).size.width - 150,
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
        ),

        ///////////////////////////////////////////////////////////////////////////////////////////
        // --- Map View Buttons (default left side)
        Positioned(
          left: settingsMgr.mapControlsRightSide.value ? null : 10,
          right: settingsMgr.mapControlsRightSide.value ? 10 : null,
          top: 10,
          bottom: 10,
          child: LayoutBuilder(builder: (context, constaints) {
            final buttonSize = max(30, min(60, constaints.maxHeight / 8)).toDouble();
            return Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment:
                    settingsMgr.mapControlsRightSide.value ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // --- Compass
                  MapButton(
                      size: buttonSize,
                      onPressed: () => {
                            setState(
                              () {
                                settingsMgr.northlockMap.value = !settingsMgr.northlockMap.value;
                                if (settingsMgr.northlockMap.value) mapController.rotate(0);

                                addAttribute("view_map_northLockMap", settingsMgr.northlockMap.value);
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
                                      ? Matrix4.rotationZ(mapController.camera.rotation * pi / 180)
                                      : Matrix4.rotationZ(0),
                                  child: settingsMgr.northlockMap.value
                                      ? Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: SvgPicture.asset("assets/images/compass_north.svg"),
                                        )
                                      : SvgPicture.asset("assets/images/compass.svg", fit: BoxFit.cover),
                                )),
                      ])),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- Focus on Me
                      MapButton(
                        size: buttonSize,
                        selected: focusMode == FocusMode.me,
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: SvgPicture.asset("assets/images/icon_controls_centermap_me.svg"),
                          ),
                        ),
                        onPressed: () => setFocusMode(FocusMode.me),
                      ),

                      //
                      SizedBox(
                          width: 2,
                          height: buttonSize / 3,
                          child: Container(
                            color: Colors.black,
                          )),
                      // --- Focus on Group
                      MapButton(
                        size: buttonSize,
                        selected: focusMode == FocusMode.group,
                        onPressed: () => setFocusMode(FocusMode.group),
                        child: Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: SvgPicture.asset("assets/images/icon_controls_centermap_group.svg"),
                        ),
                      ),
                    ],
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    // --- Zoom In (+)
                    MapButton(
                      size: buttonSize,
                      selected: false,
                      onPressed: () {
                        mapController.move(mapController.camera.center, mapController.camera.zoom + 1);
                        debugPrint("Map Zoom: ${mapController.camera.zoom}");
                        lastMapChange = DateTime.now();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: SvgPicture.asset("assets/images/icon_controls_zoom_in.svg"),
                      ),
                    ),
                    //
                    SizedBox(
                        width: 2,
                        height: buttonSize / 3,
                        child: Container(
                          color: Colors.black,
                        )),
                    // --- Zoom Out (-)
                    MapButton(
                      size: buttonSize,
                      selected: false,
                      onPressed: () {
                        mapController.move(mapController.camera.center, mapController.camera.zoom - 1);
                        debugPrint("Map Zoom: ${mapController.camera.zoom}");
                        lastMapChange = DateTime.now();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: SvgPicture.asset("assets/images/icon_controls_zoom_out.svg"),
                      ),
                    ),
                  ]),

                  // --- Measurement
                  MapButton(
                    size: buttonSize,
                    onPressed: () {
                      if (focusMode == FocusMode.measurement) {
                        measurementPoints.clear();
                        setFocusMode(prevFocusMode);
                      } else {
                        setFocusMode(FocusMode.measurement);
                      }
                      // setFocusMode(FocusMode.measurement);
                    },
                    selected: false,
                    child: Icon(
                      focusMode == FocusMode.measurement ? Icons.cancel : Icons.straighten,
                      size: 30,
                      color: focusMode == FocusMode.measurement ? Colors.red : Colors.black,
                    ),
                  )
                ]);
          }),
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

        // --- Flight Timer
        Align(
          alignment: Alignment.topCenter,
          child: Consumer<MyTelemetry>(
              builder: (context, myTelemetry, _) => GestureDetector(
                    onLongPress: () {
                      if (myTelemetry.inFlight) {
                        showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                                  content: Text("dialog.confirm.manual_stop".tr()),
                                  actions: [
                                    ElevatedButton.icon(
                                        icon: const Icon(
                                          Icons.stop_circle,
                                          color: Colors.red,
                                        ),
                                        onPressed: () {
                                          myTelemetry.stopFlight();
                                          Navigator.pop(context);
                                        },
                                        label: Text("btn.Stop".tr()))
                                  ],
                                ));
                      } else {
                        myTelemetry.startFlight();
                      }
                    },
                    child: ClipRRect(
                        borderRadius:
                            const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                        child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                            child: Container(
                                color: Colors.white38,
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (myTelemetry.takeOff != null)
                                    Padding(
                                      padding: const EdgeInsets.all(10.0),
                                      child: myTelemetry.inFlight
                                          ? const Icon(
                                              Icons.circle,
                                              color: Colors.red,
                                              size: 18,
                                            )
                                          : const Icon(
                                              Icons.check_circle,
                                              color: Colors.green,
                                              size: 18,
                                            ),
                                    ),
                                  if (myTelemetry.takeOff != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: Text.rich(
                                        TextSpan(children: [
                                          richHrMin(
                                              duration: (myTelemetry.landing ?? DateTime.now())
                                                  .difference(myTelemetry.takeOff!),
                                              valueStyle:
                                                  Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black),
                                              unitStyle: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(color: Colors.grey.shade700),
                                              longUnits: true)
                                        ]),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  if (!settingsMgr.autoRecordFlight.value && myTelemetry.takeOff == null)
                                    TextButton.icon(
                                        onPressed: () {
                                          myTelemetry.startFlight();
                                        },
                                        icon: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.red,
                                        ),
                                        label: Text(
                                          "btn.Record".tr(),
                                          style: TextStyle(color: Colors.black),
                                        ))
                                ])))),
                  )),
        ),

        // --- Current waypoint info
        if (focusMode != FocusMode.addPath && focusMode != FocusMode.editPath)
          Consumer<ActivePlan>(
            builder: (context, activePlan, _) {
              final curWaypoint = activePlan.getSelectedWp();
              if (curWaypoint != null) {
                return Padding(
                  padding: const EdgeInsets.only(left: 60, right: 60, bottom: 10),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Stack(
                      children: [
                        ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                                child: Container(
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 150),
                                    color: Colors.white38,
                                    child: WaypointNavBar(activePlan: activePlan)))),
                        Positioned(
                            top: -40,
                            right: -40,
                            child: InkWell(
                              onTap: (() {
                                activePlan.selectedWp = null;
                              }),
                              child: Padding(
                                padding: const EdgeInsets.all(40),
                                child: Icon(
                                  Icons.cancel,
                                  color: const Color.fromARGB(255, 255, 100, 100).withAlpha(200),
                                  size: 20,
                                ),
                              ),
                            ))
                      ],
                    ),
                  ),
                );
              } else {
                return Container();
              }
            },
          ),

        // --- Toggle map layer
        Positioned(
            top: 10,
            right: settingsMgr.mapControlsRightSide.value ? null : 10,
            left: settingsMgr.mapControlsRightSide.value ? 10 : null,
            child: MapSelector(
                key: const Key("viewMap_mapSelector"),
                leftAlign: settingsMgr.mapControlsRightSide.value,
                isMapDialOpen: isMapDialOpen,
                curLayer: settingsMgr.mainMapTileSrc.value,
                curOpacity: settingsMgr.mainMapOpacity.value,
                hideWaypoints: hideWaypoints,
                hideWeatherObservations: hideWeatherObservations,
                onChangedWaypoints: (hidden) {
                  setState(() {
                    hideWaypoints = hidden;
                  });
                },
                onChangedWeatherObservations: (hidden) {
                  setState(() {
                    hideWeatherObservations = hidden;
                    if (!hidden) {
                      weatherServiceResetSomeTimers();
                    }
                  });
                },
                onChanged: (layer, opacity) {
                  setState(() {
                    settingsMgr.mainMapTileSrc.value = layer;
                    settingsMgr.mainMapOpacity.value = opacity;
                  });
                }))
      ]),
    );
  }
}
