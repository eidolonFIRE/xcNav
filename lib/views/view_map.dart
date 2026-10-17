import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:xcnav/views/map/map_markers.dart';
import 'package:xcnav/views/map/offscreen_pilot_indicators.dart';
import 'package:xcnav/views/map/poly_editor.dart';
import 'package:xcnav/views/map/selected_waypoint_card.dart';
import 'package:xcnav/views/map/map_status_column.dart';
import 'package:xcnav/views/map/map_view_controls.dart';
import 'package:xcnav/views/map/flight_timer.dart';
import 'package:xcnav/views/map/link_status_icon.dart';
import 'package:xcnav/views/map/edit_toolbar.dart';
import 'package:xcnav/views/map/xc_map.dart';

// dialogs
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/dialogs/tap_point.dart';
import 'package:xcnav/dialogs/airport_info.dart';
import 'package:xcnav/dialogs/airspace_info.dart';

// models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/models/map_shapes.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/models/airport_info.dart';
import 'package:xcnav/models/tfr.dart';

// misc
import 'package:xcnav/units.dart';
import 'package:xcnav/main.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/datadog.dart';
import 'package:xcnav/tfr_service.dart';
import 'package:xcnav/services/openaip_service.dart';
import 'package:xcnav/settings_service.dart';

class ViewMap extends StatefulWidget {
  const ViewMap({super.key});

  @override
  State<ViewMap> createState() => ViewMapState();
}

class ViewMapState extends State<ViewMap> with AutomaticKeepAliveClientMixin<ViewMap> {
  bool mapReady = false;
  final XcMapController mapController = XcMapController();
  DateTime? lastMapChange;

  FocusMode focusMode = FocusMode.me;
  FocusMode prevFocusMode = FocusMode.me;

  /// User is dragging something on the map layer (for less than 30 seconds)
  bool get isDragging => dragStart != null && dragStart!.isAfter(DateTime.now().subtract(const Duration(seconds: 30)));
  DateTime? dragStart;
  LatLng? draggingLatLng;
  final _waypointDrag = MapDragTracker();

  WaypointID? editingWp;
  late MapPolyEditor polyEditor;

  /// Color of the path being edited
  Color editingPathColor = Colors.amber;
  final List<LatLng> editablePoints = [];

  // ignore: annotate_overrides
  bool get wantKeepAlive => true;

  late MapPolyEditor measurementEditor;
  final List<LatLng> measurementPoints = [];

  bool hideWaypoints = false;

  bool get showAirspace =>
      settingsMgr.showAirspaceOverlay.value && settingsMgr.mainMapTileSrc.value != MapTileSrc.sectional;

  DateTime? lastSavedLastKnownLatLng;

  List<TFR>? tfrs;

  /// GPS updates come about once a second. Glide between them.
  static const followDuration = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();

    polyEditor = MapPolyEditor(
      points: editablePoints,
      pointIcon: const Icon(
        Icons.crop_square,
        size: 20,
        color: Colors.black,
      ),
      intermediateIcon: const Icon(Icons.circle_outlined, size: 20, color: Colors.black),
      onChanged: () => setState(() {}),
    );

    measurementEditor = MapPolyEditor(
      points: measurementPoints,
      pointIcon: const Icon(
        Icons.crop_square,
        size: 20,
        color: Colors.black,
      ),
      intermediateIcon: const Icon(Icons.circle_outlined, size: 20, color: Colors.black),
      onChanged: () => setState(() {}),
    );

    addAttribute("view_map_focusMode", focusMode.name);
    addAttribute("view_map_northLockMap", settingsMgr.northlockMap.value);

    settingsMgr.mapControlsRightSide.listenable.addListener(_onControlsSideChanged);
  }

  @override
  void dispose() {
    settingsMgr.mapControlsRightSide.listenable.removeListener(_onControlsSideChanged);
    super.dispose();
  }

  void _onControlsSideChanged() => setState(() {});

  void beginEditingLine(Waypoint waypoint) {
    editingPathColor = waypoint.getColor();
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
    final Geo? geo = myTelemetry.geo;
    final camera = mapController.camera.value;
    if (geo == null || camera == null) return;

    // --- Orient to gps heading
    double? bearing;
    if (!settingsMgr.northlockMap.value && (focusMode == FocusMode.me || focusMode == FocusMode.group)) {
      bearing = geo.hdg / pi * 180;
    }

    // --- Move to center
    if (focusMode == FocusMode.me) {
      mapController.moveTo(center: geo.latlng, bearing: bearing, duration: followDuration, linear: true);
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
        final camFit = MapCamera.fit(LatLngBounds.fromPoints(points), camera.size,
            padding: const EdgeInsets.all(100), bearing: bearing ?? camera.bearing, tilt: camera.tilt, maxZoom: 12);
        mapController.moveTo(
            center: camFit.center, zoom: camFit.zoom, bearing: bearing, duration: followDuration, linear: true);
      } else {
        // Preserve zoom if it has been recently overriden
        mapController.moveTo(
            center: LatLngBounds.fromPoints(points).center, bearing: bearing, duration: followDuration, linear: true);
      }
    }
  }

  bool markerIsInView(LatLng point) => mapController.camera.value?.isOnScreen(point) ?? false;

  /// Paths of multi-point waypoints. Tap to select (or flip direction), long press to edit.
  ShapeLayer buildWaypointPaths(ActivePlan plan) => ShapeLayer("waypointPaths",
      lines: plan.waypoints.values
          .where((value) => value.latlng.length > 1)
          .whereNot((element) => element.id == editingWp)
          .map((e) => MapPolyline(points: e.latlng, width: 6.0, color: e.getColor(), hitValue: e.id))
          .toList());

  /// Waypoint path under [screenPoint], if any
  WaypointID? pathAt(ActivePlan plan, Offset screenPoint) {
    final camera = mapController.camera.value;
    if (camera == null || hideWaypoints) return null;
    return buildWaypointPaths(plan).hitTestLines(camera, screenPoint).firstOrNull;
  }

  void onMapTap(BuildContext context, LatLng latlng, Offset screenPoint) {
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
      // check tap on waypoint path
      final pathId = pathAt(plan, screenPoint);
      final wp = plan.waypoints[pathId];
      if (pathId != null && wp != null) {
        // Select this path waypoint
        if (plan.selectedWp == pathId) {
          wp.toggleDirection();
        }
        plan.selectedWp = pathId;
        return;
      }
      // check tap on TFR
      for (final tfr in getLoadedTFRs() ?? <TFR>[]) {
        if (tfr.containsPoint(latlng)) {
          // Tap on TFR
          tfr.showInfoDialog(context);
          return;
        }
      }
      // check tap on airspace
      if (showAirspace) {
        final hits = openAipService.airspacesAt(latlng);
        if (hits.isNotEmpty) showAirspaceInfoDialog(context, hits);
      }
    }
  }

  void onMapLongPress(BuildContext context, LatLng latlng, Offset screenPoint) {
    final plan = Provider.of<ActivePlan>(context, listen: false);

    // Start editing path waypoint
    final pathId = pathAt(plan, screenPoint);
    if (pathId != null && focusMode != FocusMode.measurement && plan.waypoints.containsKey(pathId)) {
      beginEditingLine(plan.waypoints[pathId]!);
      return;
    }

    // Prime the editor incase we decide to make a path
    editingPathColor = Colors.amber;
    editablePoints.clear();
    editablePoints.add(latlng);
    tapPointDialog(context, latlng, setFocusMode, (Waypoint newWaypoint) {
      Provider.of<ActivePlan>(context, listen: false).updateWaypoint(newWaypoint);
    });
  }

  void onMapCameraChanged(MapCamera camera) {
    if (lastSavedLastKnownLatLng == null ||
        lastSavedLastKnownLatLng!.difference(DateTime.now()).abs() > const Duration(minutes: 2)) {
      lastSavedLastKnownLatLng = DateTime.now();
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString(
            "lastKnownLatLng", jsonEncode({"lat": camera.center.latitude, "lng": camera.center.longitude}));
      });
    }
  }

  void onUserGesture() {
    if (focusMode == FocusMode.me || focusMode == FocusMode.group) {
      // --- Unlock any focus lock
      setFocusMode(FocusMode.unlocked);
    }
  }

  void toggleNorthLock() {
    setState(() {
      settingsMgr.northlockMap.value = !settingsMgr.northlockMap.value;
      if (settingsMgr.northlockMap.value) {
        mapController.moveTo(bearing: 0, duration: const Duration(milliseconds: 300));
      }

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

  void onAirportTap(AirportInfo airport) {
    if (focusMode == FocusMode.measurement) {
      measurementEditor.add(measurementPoints, airport.latlng);
      return;
    }
    showAirportInfoDialog(context, airport, onAddWaypoint: () {
      editWaypoint(context, Waypoint(name: airport.shortName, latlngs: [airport.latlng], icon: "airport"), isNew: true)
          ?.then((newWaypoint) {
        if (newWaypoint != null && mounted) {
          Provider.of<ActivePlan>(context, listen: false).updateWaypoint(newWaypoint);
        }
      });
    });
  }

  /// Single point waypoints. Tap to select, long press to edit.
  Widget buildWaypointMarkersLayer(ActivePlan plan) {
    return MarkerLayer(
      markers: plan.waypoints.values
          .where((e) => e.latlng.length == 1 && e.id != editingWp)
          .map((e) => MapMarker(
              key: ValueKey("waypoint_${e.id}"),
              point: e.latlng[0],
              height: 60 * 0.8,
              width: 40 * 0.8,
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
    final waypoint = plan.waypoints[editingWp]!;
    final point = draggingLatLng ?? waypoint.latlng.first;
    return MarkerLayer(markers: [
      MapMarker(
          point: point,
          width: 60 * 0.8,
          height: 60 * 0.8,
          child: MapDragHandle(
            onTap: () => plan.selectedWp = editingWp,
            onDragStart: (global) {
              _waypointDrag.start(mapController, global, point);
              setState(() {
                draggingLatLng = point;
                dragStart = DateTime.now();
              });
            },
            onDragUpdate: (global) {
              final latlng = _waypointDrag.update(mapController, global);
              if (latlng != null) setState(() => draggingLatLng = latlng);
            },
            onDragEnd: () {
              _waypointDrag.end();
              dragStart = null;
            },
            child: Stack(
              children: [
                Container(
                    transformAlignment: const Alignment(0, 0),
                    transform: Matrix4.translationValues(0, -30 * 0.8, 0),
                    child: WaypointMarker(waypoint, 60 * 0.8)),
                Container(
                    transformAlignment: const Alignment(0, 0),
                    transform: Matrix4.translationValues(12, 25, 0),
                    child: const Icon(
                      Icons.open_with,
                      color: Colors.black,
                    )),
              ],
            ),
          ))
    ]);
  }

  List<ShapeLayer> buildShapes(BuildContext context, ActivePlan plan) {
    final geo = myTelemetry.geo;
    final isEditingPath = focusMode == FocusMode.addPath || focusMode == FocusMode.editPath;
    return [
      // Sectional already shows airspace
      if (showAirspace) airspaceShapes(openAipService.airspaces),

      if (tfrs != null) tfrShapes(tfrs!),

      // Other Pilot path trace
      groupTraceShapes(Provider.of<Group>(context).activePilots),

      // Flight Log
      ShapeLayer("myTrace", lines: [if (myTelemetry.flightTrace.isNotEmpty) myTelemetry.buildFlightTrace()]),

      // ADSB Proximity
      if (context.select((ADSB adsb) => adsb.enabled) && geo != null) adsbProximityShape(geo.latlng),

      // Next waypoint: path
      if (geo != null && plan.selectedWp != null)
        ShapeLayer("nextWaypoint",
            lines: plan.buildNextWpIndicator(
                geo, (settingsMgr.displayUnitDist.value == DisplayUnitsDist.metric ? 1000 : 1609.344),
                baseTiles: settingsMgr.mainMapTileSrc.value)),

      // Waypoints: paths
      if (!hideWaypoints) buildWaypointPaths(plan),

      // Measurement: yellow line
      if (focusMode == FocusMode.measurement && measurementPoints.isNotEmpty)
        ShapeLayer("measurement",
            lines: [MapPolyline(points: measurementPoints.toList(), color: Colors.orange, width: 8)]),

      // Path being edited
      if (isEditingPath)
        ShapeLayer("editingPath",
            lines: [MapPolyline(points: editablePoints.toList(), color: editingPathColor, width: 5)]),
    ];
  }

  Widget buildMap(BuildContext context, ActivePlan plan) {
    final center = myTelemetry.geo?.latlng ?? lastKnownLatLng;
    getTFRs(center).then((value) {
      if (mounted && !identical(value, tfrs)) setState(() => tfrs = value);
    });

    return XcMap(
      controller: mapController,
      tileSrc: settingsMgr.mainMapTileSrc.value,
      opacity: settingsMgr.mainMapOpacity.value,
      initialCenter: center,
      initialZoom: 11,
      minZoom: 1,
      rotateGestures: !settingsMgr.northlockMap.value,
      terrain: true,
      onMapReady: () => setState(() => mapReady = true),
      onTap: (latlng, screenPoint) => onMapTap(context, latlng, screenPoint),
      onLongPress: (latlng, screenPoint) => onMapLongPress(context, latlng, screenPoint),
      onCameraChanged: onMapCameraChanged,
      onUserGesture: onUserGesture,
      shapes: buildShapes(context, plan),
      children: [
        // https://nowcoast.noaa.gov/help/#!section=map-service-list
        // (NOAA radar overlay is disabled. If revived, MapLibre can show WMS as a raster source with a
        // `{bbox-epsg-3857}` url.)

        // Next waypoint: barbs
        if (myTelemetry.geo != null) NextWaypointBarbsLayer(plan: plan),

        // WeatherObservations
        if (!settingsMgr.hideWeatherObservations.value) const WeatherObservationsLayer(),

        // Airports (below waypoints)
        if (settingsMgr.showAirports.value) AirportsLayer(center: center, onTap: onAirportTap),

        // Waypoint markers
        if (!hideWaypoints) buildWaypointMarkersLayer(plan),

        // --- Draggable waypoints
        if (editingWp != null && plan.waypoints.containsKey(editingWp) && plan.waypoints[editingWp]!.latlng.length == 1)
          buildDraggableWaypointLayer(plan),

        // GA planes (ADSB IN)
        if (context.select((ADSB adsb) => adsb.enabled)) const AdsbPlanesLayer(),

        // Live locations other pilots
        const GroupPilotsLayer(),

        const FuelWarningLayer(),

        const MyLocationLayer(),

        // Measurement
        if (focusMode == FocusMode.measurement && measurementPoints.isNotEmpty)
          MarkerLayer(markers: measurementEditor.edit(mapController)),
        if (focusMode == FocusMode.measurement && measurementPoints.isNotEmpty)
          MarkerLayer(markers: buildMeasurementMarkers(measurementPoints)),

        // Draggable line editor
        if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath)
          MarkerLayer(markers: polyEditor.edit(mapController)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    debugPrint("Build view_map");

    // Hookup the measurement points to the active plan provider.
    Provider.of<ActivePlan>(context, listen: false).mapMeasurement = measurementPoints;

    final controlsRightSide = settingsMgr.mapControlsRightSide.value;
    final isEditing =
        focusMode == FocusMode.addPath || focusMode == FocusMode.editPath || focusMode == FocusMode.editWaypoint;

    return Container(
      color: Colors.white,
      child: Stack(alignment: Alignment.center, children: [
        // Shapes follow my position (traces, next waypoint), so rebuild with telemetry too
        ListenableBuilder(
            listenable: Listenable.merge([myTelemetry, openAipService]),
            builder: (context, _) =>
                Consumer<ActivePlan>(builder: (context, plan, child) => buildMap(context, plan))),

        // --- Pilot Direction Markers (for when pilots are out of view)
        OffscreenPilotIndicators(mapController: mapController),

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
                showAirspace: settingsMgr.showAirspaceOverlay.value,
                onChangedAirspace: (show) => setState(() => settingsMgr.showAirspaceOverlay.value = show),
                showAirports: settingsMgr.showAirports.value,
                onChangedAirports: (show) => setState(() => settingsMgr.showAirports.value = show),
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
