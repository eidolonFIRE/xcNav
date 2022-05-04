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
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/adsb.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/fuel_warning.dart';

// widgets
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/map_button.dart';
import 'package:xcnav/widgets/chat_bubble.dart';
import 'package:xcnav/widgets/map_marker.dart';
import 'package:xcnav/widgets/icon_image.dart';

// dialogs
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/dialogs/flightplan_drawer.dart';
import 'package:xcnav/dialogs/more_instruments_drawer.dart';

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

TextStyle instrLower = const TextStyle(fontSize: 35);
TextStyle instrUpper = const TextStyle(fontSize: 40);
TextStyle instrLabel = TextStyle(
    fontSize: 14, color: Colors.grey[400], fontStyle: FontStyle.italic);

class _MyHomePageState extends State<MyHomePage> {
  late MapController mapController;
  bool mapReady = false;
  FocusMode focusMode = FocusMode.me;
  FocusMode prevFocusMode = FocusMode.me;
  bool northLock = true;

  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;
  Stream<Position>? positionStream;
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

    _setupServiceStatusStream();

    // intialize the controllers
    mapController = MapController();
    mapController.onReady.then((value) => mapReady = true);

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
            handleGeomUpdate(context, fakeFlight.genFakeLocationFlight());
          });
        }
      } else {
        if (timer != null) {
          if (!positionStreamStarted) {
            positionStreamStarted = !positionStreamStarted;
            _toggleListening();
          }
          _serviceStatusStreamSubscription!.resume();
          debugPrint("--- Stopping Location Spoofer ---");
          timer?.cancel();
          timer = null;
        }
      }
    });
  }

  void _setupServiceStatusStream() {
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

      positionStream = _geolocatorPlatform.getPositionStream(
          locationSettings: locationSettings);
    }

    setState(() {
      if (_positionStreamSubscription == null) {
        _positionStreamSubscription = positionStream!.handleError((error) {
          _positionStreamSubscription?.cancel();
          _positionStreamSubscription = null;
        }).listen((position) => {handleGeomUpdate(context, position)});

        debugPrint('Listening for position updates RESUMED');
      } else {
        _positionStreamSubscription?.cancel();
        _positionStreamSubscription = null;
        debugPrint('Listening for position updates PAUSED');
      }
    });
  }

  /// Do all the things with a GPS update
  void handleGeomUpdate(BuildContext context, Position position) {
    var myTelemetry = Provider.of<MyTelemetry>(context, listen: false);
    var settings = Provider.of<Settings>(context, listen: false);
    var geo = Geo.fromPosition(position, myTelemetry.geo);

    // Update ADSB
    Provider.of<ADSB>(context, listen: false).refresh(geo);

    if (geo.lat != 0.0 || geo.lng != 0.0) {
      myTelemetry.updateGeo(geo, bypassRecording: settings.groundMode);

      if (!settings.groundMode || settings.groundModeTelemetry) {
        // TODO: better way to reduce telemetry messages
        if (Provider.of<Group>(context, listen: false).pilots.isNotEmpty) {
          Provider.of<Client>(context, listen: false)
              .sendTelemetry(geo, myTelemetry.fuel);
        }
      }
    }
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

    // --- Orient to gps heading
    if (!northLock &&
        (focusMode == FocusMode.me || focusMode == FocusMode.group)) {
      mapController.rotate(-geo.hdg / pi * 180);
    }
    // --- Move to center
    if (focusMode == FocusMode.me) {
      centerZoom = CenterZoom(
          center: LatLng(geo.lat, geo.lng), zoom: mapController.zoom);
    } else if (focusMode == FocusMode.group) {
      List<LatLng> points = Provider.of<Group>(context, listen: false)
          .pilots
          // Don't consider telemetry older than 5 minutes
          .values
          .where((_p) =>
              _p.geo.time > DateTime.now().millisecondsSinceEpoch - 5000 * 60)
          .map((e) => e.geo.latLng)
          .toList();
      points.add(LatLng(geo.lat, geo.lng));
      centerZoom = mapController.centerZoomFitBounds(
          LatLngBounds.fromPoints(points),
          options: const FitBoundsOptions(
              padding: EdgeInsets.all(100), maxZoom: 13, inside: true));
    }
    if (centerZoom != null) {
      mapController.move(centerZoom.center, centerZoom.zoom);
    }
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

  void showFlightPlan() {
    showModalBottomSheet(
        context: context,
        elevation: 0,
        constraints: const BoxConstraints(maxHeight: 500),
        builder: (BuildContext context) {
          return SafeArea(
            child: flightPlanDrawer(setFocusMode, () {
              editablePolyline.points.clear();
              Navigator.pop(context);
              setFocusMode(FocusMode.addPath);
            }, () {
              editablePolyline.points.clear();
              editablePolyline.points.addAll(
                  Provider.of<ActivePlan>(context, listen: false)
                          .selectedWp
                          ?.latlng ??
                      []);
              Navigator.popUntil(context, ModalRoute.withName("/home"));
              setFocusMode(FocusMode.editPath);
            }),
          );
        });
  }

  void showMoreInstruments(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierLabel: "Instruments",
      barrierDismissible: true,
      pageBuilder: (BuildContext context, animationIn, animationOut) {
        return moreInstrumentsDrawer();
      },
      // TODO: this could use some tuning
      transitionBuilder: (ctx, animation, _, child) {
        return FractionalTranslation(
          translation: Offset(0, animation.value - 1),
          child: child,
        );
      },
    );
  }

  Widget topInstruments(BuildContext context) {
    return GestureDetector(
      onTap: () => showMoreInstruments(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
        child: SizedBox(
          height: 64,
          child: Consumer2<MyTelemetry, Settings>(
            builder: (context, myTelementy, settings, child) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // --- Speedometer
                  Text.rich(TextSpan(children: [
                    TextSpan(
                      text: min(
                              999,
                              convertSpeedValue(settings.displayUnitsSpeed,
                                  myTelementy.geo.spd))
                          .toStringAsFixed(settings.displayUnitsSpeed ==
                                  DisplayUnitsSpeed.mps
                              ? 1
                              : 0),
                      style: instrUpper,
                    ),
                    TextSpan(
                      text: unitStrSpeed[settings.displayUnitsSpeed],
                      style: instrLabel,
                    )
                  ])),
                  const SizedBox(
                      height: 100,
                      child:
                          VerticalDivider(thickness: 2, color: Colors.black)),
                  // --- Altimeter
                  Text.rich(TextSpan(children: [
                    TextSpan(
                      text: convertDistValueFine(
                              settings.displayUnitsDist, myTelementy.geo.alt)
                          .toStringAsFixed(0),
                      style: instrUpper,
                    ),
                    TextSpan(
                        text: unitStrDistFine[settings.displayUnitsDist],
                        style: instrLabel)
                  ])),
                  const SizedBox(
                      height: 100,
                      child:
                          VerticalDivider(thickness: 2, color: Colors.black)),
                  // --- Vario
                  Text.rich(TextSpan(children: [
                    TextSpan(
                      text: min(
                              9999,
                              max(
                                  -9999,
                                  convertVarioValue(settings.displayUnitsVario,
                                      myTelementy.geo.vario)))
                          .toStringAsFixed(settings.displayUnitsVario ==
                                  DisplayUnitsVario.fpm
                              ? 0
                              : 1),
                      style: instrUpper.merge(const TextStyle(fontSize: 30)),
                    ),
                    TextSpan(
                        text: unitStrVario[settings.displayUnitsVario],
                        style: instrLabel)
                  ])),
                ]),
          ),
        ),
      ),
    );
  }

  /// Top Bar in ground support mode
  Widget groundControlBar(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Text("Ground Support", style: instrLabel),
          Card(
              color: Colors.grey[700],
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Share Position"),
                    Switch(
                        value:
                            Provider.of<Settings>(context).groundModeTelemetry,
                        onChanged: (value) =>
                            Provider.of<Settings>(context, listen: false)
                                .groundModeTelemetry = value),
                  ],
                ),
              ))
        ],
      ),
    );
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
            automaticallyImplyLeading: true,
            leadingWidth: 35,
            toolbarHeight: 64,
            title: Provider.of<Settings>(context).groundMode
                ? groundControlBar(context)
                : topInstruments(context)),
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

            // --- Map Options
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

            ListTile(
                minVerticalPadding: 20,
                leading: const Icon(Icons.radar, size: 30),
                title: Text("ADSB-in",
                    style: Theme.of(context).textTheme.headline5),
                trailing: Switch(
                  value: Provider.of<Settings>(context).adsbEnabled,
                  onChanged: (value) => {
                    Provider.of<Settings>(context, listen: false).adsbEnabled =
                        value
                  },
                ),
                subtitle: Provider.of<Settings>(context).adsbEnabled
                    ? (Provider.of<ADSB>(context).lastHeartbeat >
                            DateTime.now().millisecondsSinceEpoch - 1000 * 10)
                        ? const Text.rich(TextSpan(children: [
                            WidgetSpan(
                                child: Icon(
                              Icons.check,
                              color: Colors.green,
                            )),
                            TextSpan(text: "Connected")
                          ]))
                        : const Text.rich(TextSpan(children: [
                            WidgetSpan(
                                child: Icon(
                              Icons.link_off,
                              color: Colors.amber,
                            )),
                            TextSpan(text: "No Data")
                          ]))
                    : null),

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
                        interactiveFlags: InteractiveFlag.all &
                            (northLock
                                ? ~InteractiveFlag.rotate
                                : InteractiveFlag.all),
                        // rotation: -myTelemetry.geo.hdg,
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
                            backgroundColor:
                                const Color.fromARGB(0, 255, 255, 255),
                          ),
                        if (settings.showAirspace)
                          TileLayerOptions(
                            urlTemplate:
                                'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airspaces_geometries@EPSG%3A900913@png/{z}/{x}/{y}.png',
                            maxZoom: 17,
                            tms: true,
                            subdomains: ['1', '2'],
                            backgroundColor:
                                const Color.fromARGB(0, 255, 255, 255),
                          ),
                        if (settings.showAirspace)
                          TileLayerOptions(
                            urlTemplate:
                                'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airspaces_labels@EPSG%3A900913@png/{z}/{x}/{y}.png',
                            maxZoom: 17,
                            tms: true,
                            subdomains: ['1', '2'],
                            backgroundColor:
                                const Color.fromARGB(0, 255, 255, 255),
                          ),

                        // Flight Log
                        PolylineLayerOptions(
                            polylines: [myTelemetry.buildFlightTrace()]),

                        // ADSB Proximity
                        if (settings.adsbEnabled)
                          CircleLayerOptions(circles: [
                            CircleMarker(
                                point: myTelemetry.geo.latLng,
                                color: Colors.transparent,
                                borderStrokeWidth: 1,
                                borderColor: Colors.black54,
                                radius:
                                    settings.proximityProfile.horizontalDist,
                                useRadiusInMeter: true)
                          ]),

                        // Trip snake lines
                        PolylineLayerOptions(polylines: plan.buildTripSnake()),

                        PolylineLayerOptions(
                          polylines: [
                            plan.buildNextWpIndicator(myTelemetry.geo)
                          ],
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
                                      builder: (context) => Container(
                                          transformAlignment:
                                              const Alignment(0, 0),
                                          transform: Matrix4.rotationZ(
                                              -mapController.rotation *
                                                  pi /
                                                  180),
                                          child: MapMarker(e, 60 * 0.8)))
                                  : null)
                              .whereNotNull()
                              .toList(),
                        ),

                        // Launch Location (automatic marker)
                        if (myTelemetry.launchGeo != null)
                          MarkerLayerOptions(markers: [
                            Marker(
                                width: 40,
                                height: 60,
                                point: myTelemetry.launchGeo!.latLng,
                                builder: (ctx) => Container(
                                      transformAlignment: const Alignment(0, 0),
                                      transform: Matrix4.rotationZ(
                                          -mapController.rotation * pi / 180),
                                      child: Stack(children: [
                                        Container(
                                          transform: Matrix4.translationValues(
                                              0, -60 / 2, 0),
                                          child: Image.asset(
                                            "assets/images/pin.png",
                                            color: Colors.lightGreen,
                                          ),
                                        ),
                                        Center(
                                          child: Container(
                                            transform:
                                                Matrix4.translationValues(
                                                    0, -60 / 1.5, 0),
                                            child: const Icon(
                                              Icons.flight_takeoff,
                                              size: 60 / 2,
                                            ),
                                          ),
                                        ),
                                      ]),
                                    ))
                          ]),

                        // GA planes (ADSB IN)
                        if (settings.adsbEnabled)
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
                                        transformAlignment:
                                            const Alignment(0, 0),
                                        child: e.getIcon(myTelemetry.geo),
                                        transform:
                                            Matrix4.rotationZ(e.hdg * pi / 180),
                                      ),
                                    ),
                                  )
                                  .toList()),

                        // Live locations other pilots
                        MarkerLayerOptions(
                          markers: Provider.of<Group>(context)
                              .pilots
                              // Don't see locations older than 5minutes
                              .values
                              .where((_p) =>
                                  _p.geo.time >
                                  DateTime.now().millisecondsSinceEpoch -
                                      5000 * 60)
                              .toList()
                              .map((pilot) => Marker(
                                  point: pilot.geo.latLng,
                                  width: 40,
                                  height: 40,
                                  builder: (ctx) => Container(
                                      transformAlignment: const Alignment(0, 0),
                                      transform: Matrix4.rotationZ(
                                          -mapController.rotation * pi / 180),
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
                                child:
                                    Image.asset("assets/images/red_arrow.png"),
                                transform:
                                    Matrix4.rotationZ(myTelemetry.geo.hdg),
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
                    )),

            // --- Chat bubbles
            Consumer<ChatMessages>(
              builder: (context, chat, child) {
                // get valid bubbles
                const numSeconds = 10;
                List<Message> bubbles = [];
                for (int i = chat.messages.length - 1; i > 0; i--) {
                  if (chat.messages[i].timestamp >
                          max(
                              DateTime.now().millisecondsSinceEpoch -
                                  1000 * numSeconds,
                              chat.chatLastOpened) &&
                      chat.messages[i].pilotId !=
                          Provider.of<Profile>(context, listen: false).id) {
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
                    right: Provider.of<Settings>(context).mapControlsRightSide
                        ? 70
                        : 0,
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
                right: Provider.of<Settings>(context).mapControlsRightSide
                    ? null
                    : 20,
                left: Provider.of<Settings>(context).mapControlsRightSide
                    ? 20
                    : null,
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
              left: Provider.of<Settings>(context).mapControlsRightSide
                  ? null
                  : 10,
              right: Provider.of<Settings>(context).mapControlsRightSide
                  ? 10
                  : null,
              top: 10,
              bottom: 10,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Compass
                    MapButton(
                        child: Stack(
                            fit: StackFit.expand,
                            clipBehavior: Clip.none,
                            children: [
                              StreamBuilder(
                                  stream: mapController.mapEventStream,
                                  builder: (context, event) => Container(
                                        transformAlignment:
                                            const Alignment(0, 0),
                                        transform: mapReady
                                            ? Matrix4.rotationZ(
                                                mapController.rotation *
                                                    pi /
                                                    180)
                                            : Matrix4.rotationZ(0),
                                        child: SvgPicture.asset(
                                          "assets/images/compass.svg",
                                          fit: BoxFit.none,
                                          color: northLock ? Colors.grey : null,
                                        ),
                                      )),
                              if (northLock)
                                SvgPicture.asset(
                                  "assets/images/lock.svg",
                                  // width: 40,
                                  color: Colors.grey[900]!.withAlpha(120),
                                  // fit: BoxFit.none,
                                ),
                            ]),
                        size: 60,
                        onPressed: () => {
                              setState(
                                () {
                                  northLock = !northLock;
                                  if (northLock) mapController.rotate(0);
                                },
                              )
                            },
                        selected: false),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- Focus on Me
                        MapButton(
                          size: 60,
                          selected: focusMode == FocusMode.me,
                          child: SvgPicture.asset(
                              "assets/images/icon_controls_centermap_me.svg"),
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
                          child: SvgPicture.asset(
                              "assets/images/icon_controls_centermap_group.svg"),
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
                        child: SvgPicture.asset(
                            "assets/images/icon_controls_zoom_in.svg"),
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
                        onPressed: () => {
                          mapController.move(
                              mapController.center, mapController.zoom - 1)
                        },
                        child: SvgPicture.asset(
                            "assets/images/icon_controls_zoom_out.svg"),
                      ),
                    ]),
                    // --- Chat button
                    Stack(
                      children: [
                        MapButton(
                          size: 60,
                          selected: false,
                          onPressed: () =>
                              {Navigator.pushNamed(context, "/party")},
                          child: const Icon(
                            Icons.chat,
                            size: 30,
                            color: Colors.black,
                          ),
                        ),
                        if (Provider.of<ChatMessages>(context).numUnread > 0)
                          Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                  decoration: const BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.all(
                                          Radius.circular(10))),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Text(
                                      "${Provider.of<ChatMessages>(context).numUnread}",
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                  ))),
                      ],
                    )
                  ]),
            ),

            // Positioned(
            //     bottom: 10,
            //     left: Provider.of<Settings>(context).mapControlsRightSide
            //         ? null
            //         : 10,
            //     right: Provider.of<Settings>(context).mapControlsRightSide
            //         ? 10
            //         : null,
            //     child: ),

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
          // debugPrint("Update ETA");
          ETA etaNext = activePlan.selectedIndex != null
              ? activePlan.etaToWaypoint(myTelemetry.geo, myTelemetry.geo.spd,
                  activePlan.selectedIndex!)
              : ETA(0, 0);

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
                                      text: convertDistValueCoarse(
                                              Provider.of<Settings>(context,
                                                      listen: false)
                                                  .displayUnitsDist,
                                              etaNext.distance)
                                          .toStringAsFixed(1),
                                      style: instrLower),
                                  TextSpan(
                                      text: unitStrDistCoarse[
                                          Provider.of<Settings>(context,
                                                  listen: false)
                                              .displayUnitsDist],
                                      style: instrLabel),
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
