import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:flutter_map_line_editor/flutter_map_line_editor.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/weather_observation_service.dart';

// widgets
import 'package:xcnav/widgets/waypoint_marker.dart';
import 'package:xcnav/widgets/map_selector.dart';
import 'package:xcnav/widgets/measurement_markers.dart';

// map view parts
import 'package:xcnav/views/map/focus_mode.dart';
import 'package:xcnav/views/map/map_layers.dart';
import 'package:xcnav/views/map/offscreen_pilot_indicators.dart';
import 'package:xcnav/views/map/selected_waypoint_card.dart';
import 'package:xcnav/views/map/map_status_column.dart';
import 'package:xcnav/views/map/map_view_controls.dart';
import 'package:xcnav/views/map/flight_timer.dart';
import 'package:xcnav/views/map/link_status_icon.dart';
import 'package:xcnav/views/map/edit_toolbar.dart';

// dialogs
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/dialogs/tap_point.dart';

// models
import 'package:xcnav/models/geo.dart';
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

  bool hideWaypoints = false;

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
      if (mode != FocusMode.editPath && mode != FocusMode.editWaypoint) editingWp = null;
      if (mode == FocusMode.group) lastMapChange = null;
      debugPrint("FocusMode = $mode");

      addAttribute("view_map_focusMode", mode.name);
    });
    refreshMapView();
  }

  void refreshMapView() {
    Geo? geo = myTelemetry.geo;

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
      if ((mapKey.currentContext?.mounted ?? false) && mapKey.currentContext?.size != null) {
        mapAspectRatio = mapKey.currentContext!.size!.aspectRatio;
      }
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

  /// WORKAROUND - calculate relative offset ourselves
  LatLng? tapToLatLng(TapPosition tapPosition) {
    final widgetBox = mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (widgetBox != null) {
      final relativeTapPos = tapPosition.global - widgetBox.localToGlobal(Offset.zero);
      return mapController.camera.offsetToCrs(relativeTapPos);
    }
    return null;
  }

  void onMapTap(BuildContext context, LatLng latlng) {
    debugPrint("onMapTap: $latlng");
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

  void onMapPositionChanged(MapCamera mapPosition, bool hasGesture) {
    if (lastSavedLastKnownLatLng == null ||
        lastSavedLastKnownLatLng!.difference(DateTime.now()).abs() > const Duration(minutes: 2)) {
      lastSavedLastKnownLatLng = DateTime.now();
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString(
            "lastKnownLatLng", jsonEncode({"lat": mapPosition.center.latitude, "lng": mapPosition.center.longitude}));
      });
    }

    if (hasGesture) {
      if (focusMode == FocusMode.me || focusMode == FocusMode.group) {
        // --- Unlock any focus lock
        setFocusMode(FocusMode.unlocked);
      }
    }
  }

  void toggleNorthLock() {
    setState(() {
      settingsMgr.northlockMap.value = !settingsMgr.northlockMap.value;
      if (settingsMgr.northlockMap.value) mapController.rotate(0);

      addAttribute("view_map_northLockMap", settingsMgr.northlockMap.value);
    });
  }

  void toggleMeasurement() {
    if (focusMode == FocusMode.measurement) {
      measurementPoints.clear();
      setFocusMode(prevFocusMode);
    } else {
      setFocusMode(FocusMode.measurement);
    }
  }

  // --- Edit toolbar actions

  void onEditDelete() {
    if (editingWp != null) {
      final plan = Provider.of<ActivePlan>(context, listen: false);
      plan.removeWaypoint(editingWp!);
      editingWp = null;
    }
    setFocusMode(prevFocusMode);
  }

  void onEditUndo() {
    draggingLatLng = null;
    setFocusMode(prevFocusMode);
  }

  void onEditDetails() {
    if (editingWp != null) {
      final plan = Provider.of<ActivePlan>(context, listen: false);
      editWaypoint(context, plan.waypoints[editingWp]!, isNew: false, isPath: plan.waypoints[editingWp]!.isPath)
          ?.then((newWaypoint) {
        if (newWaypoint != null) {
          plan.updateWaypoint(newWaypoint);
        }
      });
      editingWp = null;
    }
    setFocusMode(prevFocusMode);
  }

  void onEditConfirm() {
    final plan = Provider.of<ActivePlan>(context, listen: false);
    // --- finish editing path
    if (focusMode == FocusMode.editPath || focusMode == FocusMode.addPath) {
      if (editingWp == null) {
        final temp = Waypoint(name: "", latlngs: editablePoints.toList());
        editWaypoint(context, temp, isNew: focusMode == FocusMode.addPath, isPath: true)?.then((newWaypoint) {
          if (newWaypoint != null) {
            plan.updateWaypoint(newWaypoint);
          }
        });
      } else {
        plan.moveWaypoint(editingWp!, editablePoints.toList());
        editingWp = null;
      }
    }
    // --- finish editing waypoint
    if (focusMode == FocusMode.editWaypoint && draggingLatLng != null && editingWp != null) {
      plan.moveWaypoint(editingWp!, [draggingLatLng!]);
    }
    setFocusMode(prevFocusMode);
  }

  // --- Waypoint layers

  /// Waypoint paths. Tap to select (or flip direction), long press to edit.
  Widget buildWaypointPathsLayer(ActivePlan plan, LayerHitNotifier<String> polylineHit) {
    return GestureDetector(
      onTapDown: (details) {
        if (focusMode == FocusMode.measurement) {
          measurementEditor.add(measurementPoints, mapController.camera.offsetToCrs(details.localPosition));
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
            .map((e) => Polyline(points: e.latlng, strokeWidth: 6.0, color: e.getColor(), hitValue: e.id))
            .toList(),
      ),
    );
  }

  /// Single point waypoints. Tap to select, long press to edit.
  Widget buildWaypointMarkersLayer(ActivePlan plan) {
    return MarkerLayer(
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
                    editingWp = e.id;
                    setFocusMode(FocusMode.editWaypoint);
                  }
                },
                child: WaypointMarker(e, 60 * 0.8),
              )))
          .toList(),
    );
  }

  /// The single point waypoint currently being edited.
  Widget buildDraggableWaypointLayer(ActivePlan plan) {
    return DragMarkers(markers: [
      DragMarker(
          point: draggingLatLng ?? plan.waypoints[editingWp]!.latlng.first,
          size: const Size(60 * 0.8, 60 * 0.8),
          onTap: (_) => plan.selectedWp = editingWp,
          onDragEnd: (p0, p1) {
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
    ]);
  }

  Widget buildMap(BuildContext context, ActivePlan plan, LayerHitNotifier<String> polylineHit) {
    final showWeatherObservations =
        mapReady && !settingsMgr.hideWeatherObservations.value && mapController.camera.zoom > 7;

    return FlutterMap(
      key: mapKey,
      mapController: mapController,
      options: MapOptions(
        onMapReady: () {
          setState(() {
            mapReady = true;
          });
        },
        interactionOptions: InteractionOptions(
            flags:
                InteractiveFlag.all & (settingsMgr.northlockMap.value ? ~InteractiveFlag.rotate : InteractiveFlag.all)),
        initialCenter: myTelemetry.geo?.latlng ?? lastKnownLatLng,
        initialZoom: 12.0,
        minZoom: 2,
        onTap: (tapPosition, point) {
          final latlng = tapToLatLng(tapPosition);
          if (latlng != null) onMapTap(context, latlng);
        },
        onLongPress: (tapPosition, point) {
          final latlng = tapToLatLng(tapPosition);
          if (latlng != null) onMapLongPress(context, latlng);
        },
        onPositionChanged: onMapPositionChanged,
      ),
      children: [
        Opacity(opacity: settingsMgr.mainMapOpacity.value, child: getMapTileLayer(settingsMgr.mainMapTileSrc.value)),

        TfrLayer(center: myTelemetry.geo?.latlng ?? lastKnownLatLng),

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
          PolylineLayer(polylines: Provider.of<Group>(context).activePilots.map((e) => e.buildFlightTrace()).toList()),

        // Flight Log
        if (myTelemetry.flightTrace.isNotEmpty) PolylineLayer(polylines: [myTelemetry.buildFlightTrace()]),

        // ADSB Proximity
        if (Provider.of<ADSB>(context, listen: false).enabled && myTelemetry.geo != null) const AdsbProximityLayer(),

        // Next waypoint: path
        if (myTelemetry.geo != null && plan.selectedWp != null)
          ListenableBuilder(
            listenable: myTelemetry,
            builder: (context, _) => PolylineLayer(
                polylines: plan.buildNextWpIndicator(
                    myTelemetry.geo!, (settingsMgr.displayUnitDist.value == DisplayUnitsDist.metric ? 1000 : 1609.344),
                    baseTiles: settingsMgr.mainMapTileSrc.value)),
          ),

        // Waypoints: paths
        if (!hideWaypoints) buildWaypointPathsLayer(plan, polylineHit),

        // Next waypoint: barbs
        if (myTelemetry.geo != null) NextWaypointBarbsLayer(plan: plan),

        // Measurement: yellow line
        if (focusMode == FocusMode.measurement && measurementPoints.isNotEmpty)
          PolylineLayer(polylines: [Polyline(points: measurementPoints, color: Colors.orange, strokeWidth: 8)]),

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
        if (showWeatherObservations) WeatherObservationLabelsLayer(bounds: mapController.camera.visibleBounds),
        if (showWeatherObservations) WeatherObservationArrowsLayer(bounds: mapController.camera.visibleBounds),

        // Waypoint markers
        if (!hideWaypoints) buildWaypointMarkersLayer(plan),

        // --- Draggable waypoints
        if (editingWp != null && plan.waypoints.containsKey(editingWp) && plan.waypoints[editingWp]!.latlng.length == 1)
          buildDraggableWaypointLayer(plan),

        // GA planes (ADSB IN)
        if (Provider.of<ADSB>(context, listen: true).enabled) AdsbPlanesLayer(mapController: mapController),

        // Live locations other pilots
        GroupPilotsLayer(mapController: mapController),

        const FuelWarningLayer(),

        const MyLocationLayer(),

        // Measurement Polyline
        if (focusMode == FocusMode.measurement && measurementPoints.isNotEmpty)
          DragMarkers(markers: measurementEditor.edit()),
        if (focusMode == FocusMode.measurement && measurementPoints.isNotEmpty)
          MarkerLayer(markers: buildMeasurementMarkers(measurementPoints)),

        // Draggable line editor
        if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath) PolylineLayer(polylines: polyLines),
        if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath) DragMarkers(markers: polyEditor.edit()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    debugPrint("Build view_map");

    // Hookup the measurement points to the active plan provider.
    Provider.of<ActivePlan>(context, listen: false).mapMeasurement = measurementPoints;

    final LayerHitNotifier<String> polylineHit = ValueNotifier(null);

    settingsMgr.mapControlsRightSide.listenable.addListener(() => setState(() {}));

    final controlsRightSide = settingsMgr.mapControlsRightSide.value;
    final isEditing =
        focusMode == FocusMode.addPath || focusMode == FocusMode.editPath || focusMode == FocusMode.editWaypoint;

    return Container(
      color: Colors.white,
      child: Stack(alignment: Alignment.center, children: [
        // NOTE: MyTelemetry is not part of this consumer because refreshMapView is already called elsewhere on MyTelemetry changes
        Consumer<ActivePlan>(builder: (context, plan, child) => buildMap(context, plan, polylineHit)),

        // --- Pilot Direction Markers (for when pilots are out of view)
        OffscreenPilotIndicators(mapController: mapController, isInView: markerIsInView),

        // --- Current waypoint info
        if (!isEditing) const SelectedWaypointCard(),

        // --- Secondary column (default to right side)
        Positioned(
          left: controlsRightSide ? 10 : null,
          right: controlsRightSide ? null : 10,
          top: 10,
          bottom: 10,
          child: const MapStatusColumn(),
        ),

        // --- Map View Buttons (default left side)
        Positioned(
          left: controlsRightSide ? null : 10,
          right: controlsRightSide ? 10 : null,
          top: 10,
          bottom: 10,
          child: MapViewControls(
            mapController: mapController,
            mapReady: mapReady,
            focusMode: focusMode,
            onSetFocusMode: setFocusMode,
            onToggleNorthLock: toggleNorthLock,
            onToggleMeasurement: toggleMeasurement,
            onZoom: () => lastMapChange = DateTime.now(),
            layerSelectorBuilder: (buttonSize) => MapSelector(
                key: const Key("viewMap_mapSelector"),
                size: buttonSize,
                showAdsb: true,
                curLayer: settingsMgr.mainMapTileSrc.value,
                curOpacity: settingsMgr.mainMapOpacity.value,
                hideWaypoints: hideWaypoints,
                hideWeatherObservations: settingsMgr.hideWeatherObservations.value,
                onChangedWaypoints: (hidden) {
                  setState(() {
                    hideWaypoints = hidden;
                  });
                },
                onChangedWeatherObservations: (hidden) {
                  setState(() {
                    settingsMgr.hideWeatherObservations.value = hidden;
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
                }),
          ),
        ),

        // --- Flight Timer
        const Align(alignment: Alignment.topCenter, child: FlightTimer()),

        // --- Editing waypoint/path buttons
        if (isEditing)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(left: 80, right: 80, bottom: 10),
              child: EditToolbar(
                onDelete: onEditDelete,
                onUndo: onEditUndo,
                onEdit: focusMode != FocusMode.addPath ? onEditDetails : null,
                onConfirm: (editablePoints.length > 1 || focusMode == FocusMode.editWaypoint) &&
                        focusMode != FocusMode.measurement
                    ? onEditConfirm
                    : null,
              ),
            ),
          ),

        // --- Link status (cellular / mesh)
        Positioned(
          top: 10,
          right: controlsRightSide ? null : 10,
          left: controlsRightSide ? 10 : null,
          child: const LinkStatusIcon(),
        )
      ]),
    );
  }
}
