import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_dragmarker/dragmarker.dart';
import 'package:flutter_map_line_editor/polyeditor.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:geolocator/geolocator.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/chat.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/widgets/fuel_warning.dart';
import 'package:xcnav/widgets/icon_image.dart';

// widgets
import 'package:xcnav/widgets/waypoint_card.dart';
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/map_button.dart';
import 'package:xcnav/widgets/chat_bubble.dart';
import 'package:xcnav/widgets/map_marker.dart';

// dialogs
import 'package:xcnav/dialogs/fuel_adjustment.dart';
import 'package:xcnav/dialogs/edit_waypoint.dart';

// models
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/message.dart';

import 'package:xcnav/fake_path.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum FocusMode {
  unlocked,
  me,
  group,
  addWaypoint,
  addPath,
  editPath,
}

class _MyHomePageState extends State<MyHomePage> {
  late MapController mapController;
  FocusMode focusMode = FocusMode.me;
  FocusMode prevFocusMode = FocusMode.me;

  static TextStyle instrLower = const TextStyle(fontSize: 35);
  static TextStyle instrUpper = const TextStyle(fontSize: 40);
  static TextStyle instrLabel = TextStyle(
      fontSize: 14, color: Colors.grey[400], fontStyle: FontStyle.italic);

  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;
  bool positionStreamStarted = false;

  late PolyEditor polyEditor;

  List<Polyline> polyLines = [];
  var editablePolyline =
      Polyline(color: Colors.amber, points: [], strokeWidth: 5);

  @override
  _MyHomePageState();

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _toggleServiceStatusStream();

    // intialize the controllers
    mapController = MapController();

    polyEditor = PolyEditor(
      addClosePathMarker: false,
      points: editablePolyline.points,
      pointIcon: const Icon(
        Icons.crop_square,
        size: 23,
        color: Colors.black,
      ),
      intermediateIcon: const Icon(Icons.lens, size: 15, color: Colors.black),
      callbackRefresh: () => {setState(() {})},
    );

    polyLines.add(editablePolyline);

    // --- Location Spoofer for debugging
    FakeFlight fakeFlight = FakeFlight();
    Timer? timer;
    Provider.of<Settings>(context, listen: false).addListener(() {
      if (Provider.of<Settings>(context, listen: false).spoofLocation) {
        if (timer == null) {
          if (positionStreamStarted) {
            positionStreamStarted = !positionStreamStarted;
            _toggleListening();
          }
          debugPrint("--- Starting Location Spoofer ---");
          timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
            Provider.of<MyTelemetry>(context, listen: false).updateGeo(
                Geo.fromPosition(fakeFlight.genFakeLocationFlight(),
                    Provider.of<MyTelemetry>(context, listen: false).geo));
            refreshMapView();
          });
        }
      } else {
        if (timer != null) {
          if (!positionStreamStarted) {
            positionStreamStarted = !positionStreamStarted;
            _toggleListening();
          }
          debugPrint("--- Stopping Location Spoofer ---");
          timer?.cancel();
          timer = null;
        }
      }
    });
  }

  void _toggleServiceStatusStream() {
    debugPrint("Toggle Location Service Stream");
    if (_serviceStatusStreamSubscription == null) {
      final serviceStatusStream = _geolocatorPlatform.getServiceStatusStream();
      _serviceStatusStreamSubscription =
          serviceStatusStream.handleError((error) {
        _serviceStatusStreamSubscription?.cancel();
        _serviceStatusStreamSubscription = null;
      }).listen((serviceStatus) {
        if (serviceStatus == ServiceStatus.enabled) {
          if (positionStreamStarted) {
            _toggleListening();
          }
          if (defaultTargetPlatform == TargetPlatform.iOS &&
              !positionStreamStarted) {
            positionStreamStarted = true;
            _toggleListening();
          }
          debugPrint("Location Service Enabled");
        } else {
          if (_positionStreamSubscription != null) {
            setState(() {
              _positionStreamSubscription?.cancel();
              _positionStreamSubscription = null;
              debugPrint('Position Stream has been canceled');
            });
          }
          debugPrint("Location Service Disabled");
        }
      });

      // Initial start of the position stream
      if (!positionStreamStarted &&
          defaultTargetPlatform == TargetPlatform.android) {
        positionStreamStarted = true;
        _toggleListening();
      }
    }
  }

  void _toggleListening() {
    debugPrint("Toggle Location Listening");
    if (_positionStreamSubscription == null) {
      late LocationSettings locationSettings;

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            forceLocationManager: false,
            intervalDuration: const Duration(seconds: 5),
            //(Optional) Set foreground notification config to keep the app alive
            //when going to the background
            foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationText: "Still sending your position to the group.",
                notificationTitle: "xcNav",
                // TODO: this is broken in the lib right now.
                // notificationIcon:  name: "assets/images/xcnav.logo.wing.bw.png"}));
                enableWakeLock: true));
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.best,
          // activityType: ActivityType.fitness,
          distanceFilter: 0,
          pauseLocationUpdatesAutomatically: false,
          // Only set to true if our app will be started up in the background.
          showBackgroundLocationIndicator: false,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        );
      }

      final positionStream = _geolocatorPlatform.getPositionStream(
          locationSettings: locationSettings);
      _positionStreamSubscription = positionStream.handleError((error) {
        _positionStreamSubscription?.cancel();
        _positionStreamSubscription = null;
      }).listen((position) => {handleGeomUpdate(context, position)});
      _positionStreamSubscription?.pause();
    }

    setState(() {
      if (_positionStreamSubscription == null) {
        return;
      }

      String statusDisplayValue;
      if (_positionStreamSubscription!.isPaused) {
        _positionStreamSubscription!.resume();
        statusDisplayValue = 'resumed';
      } else {
        _positionStreamSubscription!.pause();
        statusDisplayValue = 'paused';
      }

      debugPrint('Listening for position updates $statusDisplayValue');
    });
  }

  void handleGeomUpdate(BuildContext context, Position geo) {
    Provider.of<MyTelemetry>(context, listen: false).updateGeo(Geo.fromPosition(
        geo, Provider.of<MyTelemetry>(context, listen: false).geo));
    refreshMapView();
  }

  void setFocusMode(FocusMode mode, [LatLng? center]) {
    setState(() {
      prevFocusMode = focusMode;
      focusMode = mode;
      debugPrint("FocusMode = $mode");
    });
    refreshMapView();
  }

  void refreshMapView() {
    Geo geo = Provider.of<MyTelemetry>(context, listen: false).geo;
    CenterZoom? centerZoom;
    if (focusMode == FocusMode.me) {
      centerZoom = CenterZoom(
          center: LatLng(geo.lat, geo.lng), zoom: mapController.zoom);
    } else if (focusMode == FocusMode.group) {
      List<LatLng> points = Provider.of<Group>(context, listen: false)
          .pilots
          // Don't consider telemetry older than 2 minutes
          .values
          .where((_p) =>
              _p.geo.time > DateTime.now().millisecondsSinceEpoch - 2000 * 60)
          .map((e) => e.geo.latLng)
          .toList();
      points.add(LatLng(geo.lat, geo.lng));
      centerZoom = mapController.centerZoomFitBounds(
          LatLngBounds.fromPoints(points),
          options:
              const FitBoundsOptions(padding: EdgeInsets.all(80), maxZoom: 13));
    } else {
      centerZoom =
          CenterZoom(center: mapController.center, zoom: mapController.zoom);
    }
    mapController.move(centerZoom.center, centerZoom.zoom);
  }

  void onMapTap(BuildContext context, LatLng latlng) {
    debugPrint("onMapTap: $latlng");
    if (focusMode == FocusMode.addWaypoint) {
      // --- Finish adding waypoint pin
      setFocusMode(prevFocusMode);
      editWaypoint(context, true, [latlng]);
    } else if (focusMode == FocusMode.addPath ||
        focusMode == FocusMode.editPath) {
      // --- Add waypoint in path
      polyEditor.add(editablePolyline.points, latlng);
    }
  }

  void onMapLongPress(BuildContext context, LatLng latlng) {}

  // --- Flight Plan Menu
  void showFlightPlan() {
    // TODO: move map view to see whole flight plan?
    showModalBottomSheet(
        context: context,
        elevation: 0,
        constraints: const BoxConstraints(maxHeight: 500),
        builder: (BuildContext context) {
          return Consumer2<ActivePlan, MyTelemetry>(
              builder: (context, activePlan, myTelemetry, child) {
            ETA etaNext = activePlan.selectedIndex != null
                ? activePlan.etaToWaypoint(myTelemetry.geo, myTelemetry.geo.spd,
                    activePlan.selectedIndex!)
                : ETA(0, 0);
            ETA etaTrip = activePlan.etaToTripEnd(
                myTelemetry.geo.spd, activePlan.selectedIndex ?? 0);
            etaTrip += etaNext;

            if (activePlan.includeReturnTrip && !activePlan.isReversed) {
              // optionally include eta for return trip
              etaTrip += activePlan.etaToTripEnd(myTelemetry.geo.spd, 0);
            }

            int etaTripMin = (etaTrip.time / 60000).ceil();
            String etaTripValue = (etaTripMin >= 60)
                ? (etaTripMin / 60).toStringAsFixed(1)
                : etaTripMin.toString();
            String etaTripUnit = (etaTripMin >= 60) ? "hr" : "min";

            return Column(
              children: [
                // Waypoint menu buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // --- Add New Waypoint
                    IconButton(
                        iconSize: 25,
                        onPressed: () {
                          Navigator.pop(context);
                          setFocusMode(FocusMode.addWaypoint);
                        },
                        icon: const ImageIcon(
                            AssetImage("assets/images/add_waypoint_pin.png"),
                            color: Colors.lightGreen)),
                    // --- Add New Path
                    IconButton(
                        iconSize: 25,
                        onPressed: () {
                          editablePolyline.points.clear();
                          Navigator.pop(context);
                          setFocusMode(FocusMode.addPath);
                        },
                        icon: const ImageIcon(
                            AssetImage("assets/images/add_waypoint_path.png"),
                            color: Colors.yellow)),
                    // --- Edit Waypoint
                    IconButton(
                      iconSize: 25,
                      onPressed: () => editWaypoint(
                        context,
                        false,
                        activePlan.selectedWp?.latlng ?? [],
                        editPointsCallback: () {
                          editablePolyline.points.clear();
                          editablePolyline.points
                              .addAll(activePlan.selectedWp?.latlng ?? []);
                          Navigator.popUntil(
                              context, ModalRoute.withName("/home"));
                          setFocusMode(FocusMode.editPath);
                        },
                      ),
                      icon: const Icon(Icons.edit),
                    ),
                    // --- Delete Selected Waypoint
                    IconButton(
                        iconSize: 25,
                        onPressed: () => activePlan.removeSelectedWaypoint(),
                        icon: const Icon(Icons.delete, color: Colors.red)),
                  ],
                ),

                Divider(
                  thickness: 2,
                  height: 0,
                  color: Colors.grey[900],
                ),

                // --- Waypoint list
                Expanded(
                  child: ListView(primary: true, children: [
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      primary: false,
                      itemCount: activePlan.waypoints.length,
                      itemBuilder: (context, i) => WaypointCard(
                        key: ValueKey(activePlan.waypoints[i]),
                        waypoint: activePlan.waypoints[i],
                        index: i,
                        isFaded: activePlan.selectedIndex != null &&
                            ((activePlan.isReversed &&
                                    i > activePlan.selectedIndex!) ||
                                (!activePlan.isReversed &&
                                    i < activePlan.selectedIndex!)),
                        onSelect: () {
                          debugPrint("Selected $i");
                          activePlan.selectWaypoint(i);
                        },
                        onToggleOptional: () {
                          activePlan.toggleOptional(i);
                        },
                        isSelected: i == activePlan.selectedIndex,
                      ),
                      onReorder: (oldIndex, newIndex) {
                        debugPrint("WP order: $oldIndex --> $newIndex");
                        activePlan.sortWaypoint(oldIndex, newIndex);
                      },
                    ),
                    if (activePlan.waypoints.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text(
                          "Flightplan is Empty",
                          textAlign: TextAlign.center,
                          style: instrLabel,
                        ),
                      ),
                    if (activePlan.waypoints.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.sync),
                            const Text(
                              " Include Return Trip",
                            ),
                            Switch(
                                value: activePlan.includeReturnTrip,
                                onChanged: (value) =>
                                    {activePlan.includeReturnTrip = value}),
                          ],
                        ),
                      )
                  ]),
                ),

                // --- Trip Options
                Divider(
                  thickness: 2,
                  height: 0,
                  color: Colors.grey[900],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            "Trip Remaining",
                            style: instrLabel,
                            // textAlign: TextAlign.left,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "Returning",
                            ),
                            Switch(
                                value: activePlan.isReversed,
                                activeThumbImage: IconImageProvider(
                                    Icons.arrow_upward,
                                    color: Colors.black),
                                inactiveThumbImage: IconImageProvider(
                                    Icons.arrow_downward,
                                    color: Colors.black),
                                onChanged: (value) =>
                                    {activePlan.isReversed = value}),
                          ],
                        ),
                      ],
                    ),
                    // --- Trip ETA
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: etaTrip.miles(), style: instrLower),
                          TextSpan(text: " mi", style: instrLabel),
                          if (myTelemetry.inFlight)
                            TextSpan(
                              text: "   " + etaTripValue,
                              style: instrLower,
                            ),
                          if (myTelemetry.inFlight)
                            TextSpan(text: etaTripUnit, style: instrLabel),
                          if (myTelemetry.inFlight &&
                              myTelemetry.fuel > 0 &&
                              myTelemetry.fuelTimeRemaining < etaNext.time)
                            const WidgetSpan(
                                child: Padding(
                              padding: EdgeInsets.only(left: 20),
                              child: FuelWarning(35),
                            )),
                        ]),
                      ),
                    ),
                  ],
                )
              ],
            );
          });
        });
  }

  ///////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //
  // Main Build
  //
  //
  ///////////////////////////////////////////////////////////////////////////////////////////////////////
  @override
  Widget build(BuildContext context) {
    debugPrint("Build /home");
    return Scaffold(
        appBar: AppBar(
            // Here we take the value from the MyHomePage object that was created by
            // the App.build method, and use it to set our appbar title.
            automaticallyImplyLeading: true,
            leadingWidth: 35,
            toolbarHeight: 64,
            // leading: IconButton(
            //   padding: EdgeInsets.zero,
            //   icon: const Icon(
            //     Icons.menu,
            //     color: Colors.grey,
            //   ),
            //   onPressed: () => {},
            // ),
            title: SizedBox(
              height: 64,
              child: Consumer<MyTelemetry>(
                builder: (context, myTelementy, child) => Padding(
                    padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // --- Speedometer
                          Text.rich(TextSpan(children: [
                            TextSpan(
                              text: min(999,
                                      (myTelementy.geo.spd * 3.6 * km2Miles))
                                  .toStringAsFixed(0),
                              style: instrUpper,
                            ),
                            TextSpan(
                              text: " mph",
                              style: instrLabel,
                            )
                          ])),
                          const SizedBox(
                              height: 100,
                              child: VerticalDivider(
                                  thickness: 2, color: Colors.black)),
                          // --- Altimeter
                          Text.rich(TextSpan(children: [
                            TextSpan(
                              text: (myTelementy.geo.alt * meters2Feet)
                                  .toStringAsFixed(0),
                              style: instrUpper,
                            ),
                            TextSpan(text: " ft", style: instrLabel)
                          ])),
                          const SizedBox(
                              height: 100,
                              child: VerticalDivider(
                                  thickness: 2, color: Colors.black)),
                          // --- Vario
                          Text.rich(TextSpan(children: [
                            TextSpan(
                              text: min(
                                      9999,
                                      max(
                                          -9999,
                                          (myTelementy.geo.vario *
                                              meters2Feet *
                                              60)))
                                  .toStringAsFixed(0),
                              style: instrUpper
                                  .merge(const TextStyle(fontSize: 30)),
                            ),
                            TextSpan(text: " ft/m", style: instrLabel)
                          ])),
                        ])),
              ),
            )),
        // --- Main Menu
        drawer: Drawer(
            child: ListView(
          children: [
            // --- Profile (menu header)
            SizedBox(
              height: 110,
              child: DrawerHeader(
                  padding: EdgeInsets.zero,
                  child: Stack(children: [
                    Positioned(
                      left: 10,
                      top: 10,
                      child:
                          AvatarRound(Provider.of<Profile>(context).avatar, 40),
                    ),
                    Positioned(
                      left: 100,
                      right: 10,
                      top: 10,
                      bottom: 10,
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text(
                              Provider.of<Profile>(context).name ?? "???",
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.start,
                              style: Theme.of(context).textTheme.headline4,
                            ),
                          ]),
                    ),
                    Positioned(
                        right: 0,
                        bottom: 0,
                        child: IconButton(
                          iconSize: 20,
                          icon: Icon(
                            Icons.edit,
                            color: Colors.grey[700],
                          ),
                          onPressed: () {
                            Navigator.pushNamed(context, "/profileEditor");
                          },
                        ))
                  ])),
            ),

            // --- Map tile-layer selection
            ListTile(
              minVerticalPadding: 20,
              leading: const Icon(
                Icons.local_airport,
                size: 30,
              ),
              title: Text(" Airspace",
                  style: Theme.of(context).textTheme.headline5),
              trailing: Switch(
                value: Provider.of<Settings>(context).showAirspace,
                onChanged: (value) => {
                  Provider.of<Settings>(context, listen: false).showAirspace =
                      value
                },
              ),
            ),

            const Divider(
              height: 20,
            ),

            // --- Fuel Indicator
            Consumer<MyTelemetry>(
                builder: (context, myTelemetry, child) => ListTile(
                      minVerticalPadding: 0,
                      leading: const Icon(Icons.local_gas_station, size: 30),
                      title: GestureDetector(
                        onTap: () => {showFuelDialog(context)},
                        child: Card(
                          child: (myTelemetry.fuel > 0)
                              ? Builder(builder: (context) {
                                  int remMin = (myTelemetry.fuel /
                                          myTelemetry.fuelBurnRate *
                                          60)
                                      .ceil();
                                  String value = (remMin >= 60)
                                      ? (remMin / 60).toStringAsFixed(1)
                                      : remMin.toString();
                                  String unit = (remMin >= 60) ? "hr" : "min";
                                  return Row(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                                text: myTelemetry.fuel
                                                    .toStringAsFixed(1),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headline4),
                                            TextSpan(
                                                text: " L", style: instrLabel)
                                          ],
                                        ),
                                        softWrap: false,
                                      ),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                                text: value,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headline4),
                                            TextSpan(
                                                text: unit, style: instrLabel)
                                          ],
                                        ),
                                        softWrap: false,
                                      ),
                                    ],
                                  );
                                })
                              : Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Text(
                                    "Set Fuel Level",
                                    style:
                                        Theme.of(context).textTheme.headline5,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                        ),
                      ),
                    )),

            const Divider(
              height: 20,
            ),

            ListTile(
              minVerticalPadding: 20,
              onTap: () => {Navigator.pushNamed(context, "/groupDetails")},
              leading: const Icon(
                Icons.groups,
                size: 30,
              ),
              title: Text(
                "Group",
                style: Theme.of(context).textTheme.headline5,
              ),
              trailing: IconButton(
                  iconSize: 30,
                  onPressed: () => {Navigator.pushNamed(context, "/qrScanner")},
                  icon: const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.lightBlue,
                  )),
            ),

            ListTile(
              minVerticalPadding: 20,
              onTap: () => {Navigator.pushNamed(context, "/plans")},
              leading: const Icon(
                Icons.pin_drop,
                size: 30,
              ),
              title: Text(
                "Plans",
                style: Theme.of(context).textTheme.headline5,
              ),
            ),

            ListTile(
                minVerticalPadding: 20,
                onTap: () => {Navigator.pushNamed(context, "/flightLogs")},
                leading: const Icon(
                  Icons.menu_book,
                  size: 30,
                ),
                title: Text("History",
                    style: Theme.of(context).textTheme.headline5)),
            ListTile(
                minVerticalPadding: 20,
                onTap: () => {Navigator.pushNamed(context, "/settings")},
                leading: const Icon(
                  Icons.settings,
                  size: 30,
                ),
                title: Text("Settings",
                    style: Theme.of(context).textTheme.headline5)),
          ],
        )),
        body: Center(
          child: Stack(alignment: Alignment.center, children: [
            Consumer3<MyTelemetry, Settings, ActivePlan>(
              builder: (context, myTelemetry, settings, plan, child) =>
                  FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  interactiveFlags:
                      InteractiveFlag.all & ~InteractiveFlag.rotate,
                  center: myTelemetry.geo.latLng,
                  zoom: 12.0,
                  onTap: (tapPosition, point) => onMapTap(context, point),
                  onLongPress: (tapPosition, point) =>
                      onMapLongPress(context, point),
                  onPositionChanged: (mapPosition, hasGesture) {
                    // debugPrint("$mapPosition $hasGesture");
                    if (hasGesture &&
                        (focusMode == FocusMode.me ||
                            focusMode == FocusMode.group)) {
                      // --- Unlock any focus lock
                      setFocusMode(FocusMode.unlocked);
                    }
                  },
                  allowPanningOnScrollingParent: false,
                  plugins: [
                    DragMarkerPlugin(),
                  ],
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

                  if (settings.showAirspace)
                    TileLayerOptions(
                      urlTemplate:
                          'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airports@EPSG%3A900913@png/{z}/{x}/{y}.png',
                      maxZoom: 17,
                      tms: true,
                      subdomains: ['1', '2'],
                      backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                    ),
                  if (settings.showAirspace)
                    TileLayerOptions(
                      urlTemplate:
                          'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airspaces_geometries@EPSG%3A900913@png/{z}/{x}/{y}.png',
                      maxZoom: 17,
                      tms: true,
                      subdomains: ['1', '2'],
                      backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                    ),
                  if (settings.showAirspace)
                    TileLayerOptions(
                      urlTemplate:
                          'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airspaces_labels@EPSG%3A900913@png/{z}/{x}/{y}.png',
                      maxZoom: 17,
                      tms: true,
                      subdomains: ['1', '2'],
                      backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                    ),

                  // Flight Log
                  PolylineLayerOptions(
                      polylines: [myTelemetry.buildFlightTrace()]),

                  // Trip snake lines
                  PolylineLayerOptions(polylines: plan.buildTripSnake()),

                  PolylineLayerOptions(
                    polylines: [plan.buildNextWpIndicator(myTelemetry.geo)],
                  ),

                  // Flight plan paths
                  PolylineLayerOptions(
                    polylines: plan.waypoints
                        .where((value) => value.latlng.length > 1)
                        .mapIndexed((i, e) => Polyline(
                            points: e.latlng,
                            strokeWidth: 6,
                            color: Color(e.color ?? Colors.black.value)))
                        .toList(),
                  ),

                  // Flight plan markers
                  DragMarkerPluginOptions(
                    markers: plan.waypoints
                        .mapIndexed((i, e) => e.latlng.length == 1
                            ? DragMarker(
                                point: e.latlng[0],
                                height: 60 * 0.8,
                                width: 40 * 0.8,
                                onTap: (_) => plan.selectWaypoint(i),
                                onDragEnd: (p0, p1) => {
                                      plan.moveWaypoint(i, [p1])
                                    },
                                builder: (context) => MapMarker(e, 60 * 0.8))
                            : null)
                        .whereNotNull()
                        .toList(),
                  ),

                  // Live locations other pilots
                  MarkerLayerOptions(
                    markers: Provider.of<Group>(context)
                        .pilots
                        // Don't share locations older than 5minutes
                        .values
                        .where((_p) =>
                            _p.geo.time >
                            DateTime.now().millisecondsSinceEpoch - 5000 * 60)
                        .toList()
                        .map((pilot) => Marker(
                            point: pilot.geo.latLng,
                            width: 40,
                            height: 40,
                            builder: (ctx) => Container(
                                transformAlignment: const Alignment(0, 0),
                                child: AvatarRound(pilot.avatar, 40))))
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
                          child: Image.asset("assets/images/red_arrow.png"),
                          transform: Matrix4.rotationZ(myTelemetry.geo.hdg),
                        ),
                      ),
                    ],
                  ),

                  // Draggable line editor
                  if (focusMode == FocusMode.addPath ||
                      focusMode == FocusMode.editPath)
                    PolylineLayerOptions(polylines: polyLines),
                  if (focusMode == FocusMode.addPath ||
                      focusMode == FocusMode.editPath)
                    DragMarkerPluginOptions(markers: polyEditor.edit()),
                ],
              ),
            ),

            // --- Chat bubbles
            Consumer<Chat>(
              builder: (context, chat, child) {
                // get valid bubbles
                const numSeconds = 10;
                List<Message> bubbles = [];
                for (int i = chat.messages.length - 1; i > 0; i--) {
                  if (chat.messages[i].timestamp >
                      max(
                          DateTime.now().millisecondsSinceEpoch -
                              1000 * numSeconds,
                          chat.chatLastOpened)) {
                    bubbles.add(chat.messages[i]);
                    // "self destruct" the message after several seconds
                    Timer _hideBubble =
                        Timer(const Duration(seconds: numSeconds), () {
                      // TODO: This is prolly hacky... but it works for now
                      chat.notifyListeners();
                    });
                  } else {
                    break;
                  }
                }
                return Positioned(
                    right: 0,
                    bottom: 0,
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
                                AvatarRound(
                                    Provider.of<Group>(context, listen: false)
                                            .pilots[e.pilotId]
                                            ?.avatar ??
                                        Image.asset(
                                            "assets/images/default_avatar.png"),
                                    20),
                                null,
                                e.timestamp),
                          )
                          .toList(),
                    ));
              },
            ),

            // --- Map overlay layers
            if (focusMode == FocusMode.addWaypoint)
              const Positioned(
                bottom: 15,
                child: Card(
                  color: Colors.amber,
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text.rich(
                      TextSpan(children: [
                        WidgetSpan(
                            child: Icon(
                          Icons.touch_app,
                          size: 20,
                          color: Colors.black,
                        )),
                        TextSpan(text: "Tap to place waypoint")
                      ]),
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                      // textAlign: TextAlign.justify,
                    ),
                  ),
                ),
              ),
            if (focusMode == FocusMode.addPath ||
                focusMode == FocusMode.editPath)
              Positioned(
                bottom: 15,
                right: 20,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Card(
                      color: Colors.amber,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text.rich(
                          TextSpan(children: [
                            WidgetSpan(
                                child: Icon(
                              Icons.touch_app,
                              size: 20,
                              color: Colors.black,
                            )),
                            TextSpan(text: "Tap to add to path")
                          ]),
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                          // textAlign: TextAlign.justify,
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: 45,
                      icon: const Icon(
                        Icons.cancel,
                        size: 45,
                        color: Colors.red,
                      ),
                      onPressed: () => {setFocusMode(prevFocusMode)},
                    ),
                    if (editablePolyline.points.length > 1)
                      IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 45,
                        icon: const Icon(
                          Icons.check_circle,
                          size: 45,
                          color: Colors.green,
                        ),
                        onPressed: () {
                          // --- finish editing path
                          editWaypoint(context, focusMode == FocusMode.addPath,
                              editablePolyline.points);
                          setFocusMode(prevFocusMode);
                        },
                      ),
                  ],
                ),
              ),

            // --- Map View Buttons
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- Focus on Me
                        MapButton(
                          size: 60,
                          selected: focusMode == FocusMode.me,
                          child: Image.asset(
                              "assets/images/icon_controls_centermap_me.png"),
                          onPressed: () => setFocusMode(
                              FocusMode.me,
                              Provider.of<MyTelemetry>(context, listen: false)
                                  .geo
                                  .latLng),
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
                          child: Image.asset(
                              "assets/images/icon_controls_centermap_group.png"),
                        ),
                      ],
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      // --- Zoom In (+)
                      MapButton(
                        size: 60,
                        selected: false,
                        onPressed: () => {
                          mapController.move(
                              mapController.center, mapController.zoom + 1)
                        },
                        child: Image.asset(
                            "assets/images/icon_controls_zoom_in.png"),
                      ),
                      //
                      SizedBox(
                          width: 2,
                          height: 20,
                          child: Container(
                            color: Colors.black,
                          )),
                      // --- Zoom Out (-)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 60),
                        child: MapButton(
                          size: 60,
                          selected: false,
                          onPressed: () => {
                            mapController.move(
                                mapController.center, mapController.zoom - 1)
                          },
                          child: Image.asset(
                              "assets/images/icon_controls_zoom_out.png"),
                        ),
                      ),
                    ]),
                  ]),
            ),

            // --- Chat button
            Positioned(
                bottom: 10,
                left: 10,
                child: MapButton(
                  size: 60,
                  selected: false,
                  onPressed: () => {Navigator.pushNamed(context, "/party")},
                  child: const Icon(
                    Icons.chat,
                    size: 30,
                    color: Colors.black,
                  ),
                )),
            if (Provider.of<Chat>(context).numUnread > 0)
              Positioned(
                  bottom: 10,
                  left: 60,
                  child: Container(
                      decoration: const BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.all(Radius.circular(10))),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Text(
                          "${Provider.of<Chat>(context).numUnread}",
                          style: const TextStyle(fontSize: 20),
                        ),
                      ))),

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
                            TextSpan(
                                text: "  connecting",
                                style: TextStyle(
                                    color: Colors.black, fontSize: 20)),
                          ]),
                        ),
                      )))
          ]),
        ),

        // --- Bottom Instruments
        bottomNavigationBar: Consumer2<ActivePlan, MyTelemetry>(
            builder: (context, activePlan, myTelemetry, child) {
          debugPrint("Update ETA");
          ETA etaNext = activePlan.selectedIndex != null
              ? activePlan.etaToWaypoint(myTelemetry.geo, myTelemetry.geo.spd,
                  activePlan.selectedIndex!)
              : ETA(0, 0);
          // ETA etaTrip = activePlan.etaToTripEnd(
          //     myTelemetry.geo.spd, activePlan.selectedIndex ?? 0);
          // etaTrip += etaNext;

          int etaNextMin = (etaNext.time / 60000).ceil();
          String etaNextValue = (etaNextMin >= 60)
              ? (etaNextMin / 60).toStringAsFixed(1)
              : etaNextMin.toString();
          String etaNextUnit = (etaNextMin >= 60) ? "hr" : "min";

          final curWp = activePlan.selectedWp;

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // --- Previous Waypoint
              IconButton(
                onPressed: () {
                  if (activePlan.selectedIndex != null &&
                      activePlan.selectedIndex! > 0) {
                    // (Skip optional waypoints)
                    for (int i = activePlan.selectedIndex! - 1; i >= 0; i--) {
                      if (!activePlan.waypoints[i].isOptional) {
                        activePlan.selectWaypoint(i);
                        break;
                      }
                    }
                  }
                },
                iconSize: 40,
                color: (activePlan.selectedIndex != null &&
                        activePlan.selectedIndex! > 0)
                    ? Colors.white
                    : Colors.grey[700],
                icon: activePlan.isReversed
                    ? const Icon(
                        Icons.skip_previous,
                      )
                    : SvgPicture.asset(
                        "assets/images/reverse_back.svg",
                        color: ((activePlan.selectedIndex ?? 0) > 0)
                            ? Colors.white
                            : Colors.grey[700],
                      ),
              ),

              // --- Next Waypoint Info
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: GestureDetector(
                    onTap: showFlightPlan,
                    child: (curWp != null)
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // --- Current Waypoint Label
                              Text.rich(
                                TextSpan(children: [
                                  if (curWp.icon != null)
                                    WidgetSpan(
                                      child: Container(
                                        transform:
                                            Matrix4.translationValues(0, 15, 0),
                                        child: SizedBox(
                                            width: 20,
                                            height: 30,
                                            child: MapMarker(curWp, 30)),
                                      ),
                                    ),
                                  if (curWp.icon != null)
                                    const TextSpan(text: "  "),
                                  TextSpan(
                                    text: curWp.name,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 30),
                                  ),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(
                                width: MediaQuery.of(context).size.width / 2,
                                child: Divider(
                                  thickness: 2,
                                  height: 8,
                                  color: Colors.grey[900],
                                ),
                              ),
                              // --- ETA next
                              Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                      text: etaNext.miles(), style: instrLower),
                                  TextSpan(text: " mi ", style: instrLabel),
                                  if (myTelemetry.inFlight)
                                    TextSpan(
                                      text: "   " + etaNextValue,
                                      style: instrLower,
                                    ),
                                  if (myTelemetry.inFlight)
                                    TextSpan(
                                        text: etaNextUnit, style: instrLabel),
                                  if (myTelemetry.inFlight &&
                                      myTelemetry.fuel > 0 &&
                                      myTelemetry.fuelTimeRemaining <
                                          etaNext.time)
                                    const WidgetSpan(
                                        child: Padding(
                                      padding: EdgeInsets.only(left: 20),
                                      child: FuelWarning(35),
                                    )),
                                ]),
                              ),
                            ],
                          )
                        : const Text("Select Waypoint")),
              ),
              // --- Next Waypoint
              IconButton(
                onPressed: () {
                  if (activePlan.selectedIndex != null &&
                      activePlan.selectedIndex! <
                          activePlan.waypoints.length - 1) {
                    // (Skip optional waypoints)
                    for (int i = activePlan.selectedIndex! + 1;
                        i < activePlan.waypoints.length;
                        i++) {
                      if (!activePlan.waypoints[i].isOptional) {
                        activePlan.selectWaypoint(i);
                        break;
                      }
                    }
                  }
                },
                iconSize: 40,
                color: (activePlan.selectedIndex != null &&
                        activePlan.selectedIndex! <
                            activePlan.waypoints.length - 1)
                    ? Colors.white
                    : Colors.grey[700],
                icon: !activePlan.isReversed
                    ? const Icon(
                        Icons.skip_next,
                      )
                    : SvgPicture.asset(
                        "assets/images/reverse_forward.svg",
                        color: ((activePlan.selectedIndex ?? -1) <
                                activePlan.waypoints.length - 1)
                            ? Colors.white
                            : Colors.grey[700],
                      ),
              ),
            ],
          );
        }));
  }
}
