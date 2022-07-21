import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barometer/flutter_barometer.dart';
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
import 'package:xcnav/patreon.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/providers/adsb.dart';

// widgets
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/make_path_barbs.dart';
import 'package:xcnav/widgets/map_button.dart';
import 'package:xcnav/widgets/chat_bubble.dart';
import 'package:xcnav/widgets/map_marker.dart';
import 'package:xcnav/widgets/fuel_warning.dart';
import 'package:xcnav/widgets/pilot_marker.dart';

// dialogs
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/dialogs/flightplan_drawer.dart';
import 'package:xcnav/dialogs/more_instruments_drawer.dart';

// models
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/message.dart';
import 'package:xcnav/models/ga.dart';

// misc
import 'package:xcnav/fake_path.dart';
import 'package:xcnav/units.dart';

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
TextStyle instrLabel = TextStyle(fontSize: 14, color: Colors.grey.shade400, fontStyle: FontStyle.italic);

class _MyHomePageState extends State<MyHomePage> {
  late MapController mapController;
  DateTime? lastMapChange;
  final mapKey = GlobalKey(debugLabel: "mainMap");
  double? mapAspectRatio;
  bool mapReady = false;
  FocusMode focusMode = FocusMode.me;
  FocusMode prevFocusMode = FocusMode.me;
  bool northLock = true;

  StreamSubscription<BarometerValue>? listenBaro;

  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;
  Stream<Position>? positionStream;
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;
  bool positionStreamStarted = false;

  int? editingIndex;
  late PolyEditor polyEditor;

  List<Polyline> polyLines = [];
  var editablePolyline = Polyline(color: Colors.amber, points: [], strokeWidth: 5);

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
    _startBaroService();

    // intialize the controllers
    mapController = MapController();
    mapController.onReady.then((value) => mapReady = true);

    polyEditor = PolyEditor(
      addClosePathMarker: false,
      points: editablePolyline.points,
      pointIcon: const Icon(
        Icons.crop_square,
        size: 20,
        color: Colors.black,
      ),
      intermediateIcon: const Icon(Icons.circle_outlined, size: 20, color: Colors.black),
      callbackRefresh: () => {setState(() {})},
    );

    polyLines.add(editablePolyline);

    // --- Location Spoofer for debugging
    FakeFlight fakeFlight = FakeFlight();
    Timer? timer;
    Provider.of<Settings>(context, listen: false).addListener(() {
      if (Provider.of<Settings>(context, listen: false).spoofLocation) {
        if (timer == null) {
          // --- Spoof Location / Disable Baro
          listenBaro?.cancel();
          if (positionStreamStarted) {
            positionStreamStarted = !positionStreamStarted;
            _toggleListening();
          }
          debugPrint("--- Starting Location Spoofer ---");
          Provider.of<MyTelemetry>(context, listen: false).baro = null;
          fakeFlight.initFakeFlight(Provider.of<MyTelemetry>(context, listen: false).geo);
          timer = Timer.periodic(const Duration(seconds: 5), (timer) async {
            handleGeomUpdate(context, fakeFlight.genFakeLocationFlight());
          });
        }
      } else {
        if (timer != null) {
          // --- Real Location / Baro

          _startBaroService();

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

  void _startBaroService() {
    listenBaro = FlutterBarometer.currentPressureEvent.listen((event) {
      Provider.of<MyTelemetry>(context, listen: false).baro = event;
      // debugPrint("Baro: ${event.hectpascal}");
    });
  }

  void _setupServiceStatusStream() {
    debugPrint("Toggle Location Service Stream");
    if (_serviceStatusStreamSubscription == null) {
      final serviceStatusStream = _geolocatorPlatform.getServiceStatusStream();
      _serviceStatusStreamSubscription = serviceStatusStream.handleError((error) {
        _serviceStatusStreamSubscription?.cancel();
        _serviceStatusStreamSubscription = null;
      }).listen((serviceStatus) {
        if (serviceStatus == ServiceStatus.enabled) {
          if (positionStreamStarted) {
            _toggleListening();
          }
          if (defaultTargetPlatform == TargetPlatform.iOS && !positionStreamStarted) {
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
      if (!positionStreamStarted && defaultTargetPlatform == TargetPlatform.android) {
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
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.best,
          // activityType: ActivityType.fitness,
          distanceFilter: 0,
          pauseLocationUpdatesAutomatically: false,
          // Only set to true if our app will be started up in the background.
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        );
      }

      positionStream = _geolocatorPlatform.getPositionStream(locationSettings: locationSettings);
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

    if (position.latitude != 0.0 || position.longitude != 0.0) {
      myTelemetry.updateGeo(position, bypassRecording: settings.groundMode);

      if (!settings.groundMode || settings.groundModeTelemetry) {
        if (Provider.of<Group>(context, listen: false).pilots.isNotEmpty) {
          Provider.of<Client>(context, listen: false).sendTelemetry(myTelemetry.geo, myTelemetry.fuel);
        }
      }
    }

    // Update ADSB
    Provider.of<ADSB>(context, listen: false).refresh(myTelemetry.geo);
    refreshMapView();
  }

  void setFocusMode(FocusMode mode, [LatLng? center]) {
    setState(() {
      prevFocusMode = focusMode;
      focusMode = mode;
      if (mode != FocusMode.editPath) editingIndex = null;
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
      List<LatLng> points = Provider.of<Group>(context, listen: false)
          .pilots
          // Don't consider telemetry older than 5 minutes
          .values
          .where((_p) => _p.geo.time > DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch)
          .map((e) => e.geo.latLng)
          .toList();
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
    if (focusMode == FocusMode.addWaypoint) {
      // --- Finish adding waypoint pin
      setFocusMode(prevFocusMode);
      editWaypoint(context, Waypoint("", [latlng], false, null, null), isNew: true)?.then((newWaypoint) {
        if (newWaypoint != null) {
          var plan = Provider.of<ActivePlan>(context, listen: false);
          plan.insertWaypoint(
              plan.waypoints.length, newWaypoint.name, newWaypoint.latlng, false, newWaypoint.icon, newWaypoint.color);
        }
      });
    } else if (focusMode == FocusMode.addPath || focusMode == FocusMode.editPath) {
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
            child: Dismissible(
              key: const Key("flightPlanDrawer"),
              direction: DismissDirection.down,
              resizeDuration: const Duration(milliseconds: 10),
              onDismissed: (event) => Navigator.pop(context),
              child: flightPlanDrawer(setFocusMode, () {
                // onNewPath
                editablePolyline.points.clear();
                Navigator.popUntil(context, ModalRoute.withName("/home"));
                setFocusMode(FocusMode.addPath);
              }, (int index) {
                // onEditPointsCallback
                debugPrint("Editing Index $index");
                editingIndex = index;
                editablePolyline.points.clear();
                editablePolyline.points.addAll(Provider.of<ActivePlan>(context, listen: false).waypoints[index].latlng);
                Navigator.popUntil(context, ModalRoute.withName("/home"));
                setFocusMode(FocusMode.editPath);
              }),
            ),
          );
        });
  }

  void showMoreInstruments(BuildContext context) {
    Provider.of<Wind>(context, listen: false).clearStopTrigger();
    showGeneralDialog(
      context: context,
      barrierLabel: "Instruments",
      barrierDismissible: true,
      pageBuilder: (BuildContext context, animationIn, animationOut) {
        return Dismissible(
          key: const Key("moreInstruments"),
          resizeDuration: const Duration(milliseconds: 10),
          child: moreInstrumentsDrawer(),
          direction: DismissDirection.up,
          onDismissed: (event) {
            Navigator.pop(context);
            final wind = Provider.of<Wind>(context, listen: false);
            wind.stop(waitTillSolution: true);
          },
        );
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
      onPanDown: (event) => showMoreInstruments(context),
      // onTap: () => showMoreInstruments(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
        child: Container(
          color: Theme.of(context).backgroundColor,
          child: SizedBox(
            height: 64,
            child: Consumer2<MyTelemetry, Settings>(
              builder: (context, myTelementy, settings, child) =>
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                // --- Speedometer
                Text.rich(TextSpan(children: [
                  TextSpan(
                    text: printValue(
                        value: convertSpeedValue(settings.displayUnitsSpeed, myTelementy.geo.spd),
                        digits: 3,
                        decimals: settings.displayUnitsSpeed == DisplayUnitsSpeed.mps ? 1 : 0),
                    style: instrUpper,
                  ),
                  TextSpan(
                    text: unitStrSpeed[settings.displayUnitsSpeed],
                    style: instrLabel,
                  )
                ])),
                const SizedBox(height: 100, child: VerticalDivider(thickness: 2, color: Colors.black)),
                // --- Altimeter
                Text.rich(TextSpan(children: [
                  TextSpan(
                    text: printValue(
                        value: convertDistValueFine(settings.displayUnitsDist, myTelementy.geo.alt),
                        digits: 5,
                        decimals: 0),
                    style: instrUpper,
                  ),
                  TextSpan(text: unitStrDistFine[settings.displayUnitsDist], style: instrLabel)
                ])),
                const SizedBox(height: 100, child: VerticalDivider(thickness: 2, color: Colors.black)),
                // --- Vario
                Text.rich(TextSpan(children: [
                  TextSpan(
                    text: printValue(
                        value: convertVarioValue(settings.displayUnitsVario, myTelementy.geo.vario),
                        digits: 3,
                        decimals: settings.displayUnitsVario == DisplayUnitsVario.fpm ? 0 : 1),
                    style: instrUpper.merge(const TextStyle(fontSize: 30)),
                  ),
                  TextSpan(text: unitStrVario[settings.displayUnitsVario], style: instrLabel)
                ])),
              ]),
            ),
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
              color: Colors.grey.shade700,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Share Position"),
                    Switch(
                        value: Provider.of<Settings>(context).groundModeTelemetry,
                        onChanged: (value) =>
                            Provider.of<Settings>(context, listen: false).groundModeTelemetry = value),
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top]);
    return Scaffold(
        appBar: AppBar(
            automaticallyImplyLeading: true,
            leadingWidth: 35,
            toolbarHeight: 64,
            title: Provider.of<Settings>(context).groundMode ? groundControlBar(context) : topInstruments(context)),
        // --- Main Menu
        drawer: Drawer(
            child: ListView(
          children: [
            // --- Profile (menu header)
            SizedBox(
              height: 110,
              child: DrawerHeader(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 1, color: Colors.grey.shade700))),
                  padding: EdgeInsets.zero,
                  child: Stack(children: [
                    Positioned(
                      left: 10,
                      top: 10,
                      child: AvatarRound(
                        Provider.of<Profile>(context).avatar,
                        40,
                        tier: Provider.of<Profile>(context, listen: false).tier,
                      ),
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
                            color: Colors.grey.shade700,
                          ),
                          onPressed: () {
                            Navigator.pushNamed(context, "/profileEditor");
                          },
                        )),
                    if (isTierRecognized(Provider.of<Profile>(context, listen: false).tier))
                      Positioned(
                          top: 10, right: 10, child: tierBadge(Provider.of<Profile>(context, listen: false).tier)),
                  ])),
            ),

            // --- Map Options
            Builder(builder: (context) {
              final settings = Provider.of<Settings>(context, listen: false);
              return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: settings.mapTileThumbnails.keys
                      .map((e) => SizedBox(
                            width: 100,
                            height: 60,
                            child: GestureDetector(
                                onTap: () => {settings.curMapTiles = e},
                                child: Container(
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: e == settings.curMapTiles ? Colors.lightBlue : Colors.grey.shade900,
                                            width: 4)),
                                    margin: const EdgeInsets.all(4),
                                    clipBehavior: Clip.antiAlias,
                                    child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: settings.mapTileThumbnails[e]))),
                          ))
                      .toList());
            }),

            // --- Map opacity slider
            if (Provider.of<Settings>(context).curMapTiles != "topo")
              Builder(builder: (context) {
                final settings = Provider.of<Settings>(context, listen: false);
                return Slider(
                    label: "Opacity",
                    activeColor: Colors.lightBlue,
                    value: settings.mapOpacity(settings.curMapTiles),
                    onChanged: (value) => settings.setMapOpacity(settings.curMapTiles, value));
              }),

            // --- Toggle airspace overlay
            if (Provider.of<Settings>(context).curMapTiles == "topo")
              ListTile(
                minVerticalPadding: 20,
                leading: const Icon(
                  Icons.local_airport,
                  size: 30,
                ),
                title: Text("Airspace", style: Theme.of(context).textTheme.headline5),
                trailing: Switch(
                  activeColor: Colors.lightBlueAccent,
                  value: Provider.of<Settings>(context).showAirspace,
                  onChanged: (value) => {Provider.of<Settings>(context, listen: false).showAirspace = value},
                ),
              ),

            ListTile(
                minVerticalPadding: 20,
                leading: const Icon(Icons.radar, size: 30),
                title: Text("ADSB-in", style: Theme.of(context).textTheme.headline5),
                trailing: Switch(
                  activeColor: Colors.lightBlueAccent,
                  value: Provider.of<ADSB>(context).enabled,
                  onChanged: (value) => {Provider.of<ADSB>(context, listen: false).enabled = value},
                ),
                subtitle: Provider.of<ADSB>(context).enabled
                    ? (Provider.of<ADSB>(context).lastHeartbeat > DateTime.now().millisecondsSinceEpoch - 1000 * 60)
                        ? const Text.rich(TextSpan(children: [
                            WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Icon(
                                  Icons.check,
                                  color: Colors.green,
                                )),
                            TextSpan(text: "  Connected")
                          ]))
                        : Text.rich(TextSpan(children: [
                            const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Icon(
                                  Icons.link_off,
                                  color: Colors.amber,
                                )),
                            const TextSpan(text: "  No Data"),
                            WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 15),
                                  child: GestureDetector(
                                      onTap: () => {Navigator.pushNamed(context, "/adsbHelp")},
                                      child: const Icon(Icons.help, size: 20, color: Colors.lightBlueAccent)),
                                )),
                          ]))
                    : null),

            Divider(height: 20, thickness: 1, color: Colors.grey.shade700),

            /// Group
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
                "Waypoints",
                style: Theme.of(context).textTheme.headline5,
              ),
            ),

            ListTile(
              minVerticalPadding: 20,
              leading: const Icon(
                Icons.cloudy_snowing,
                size: 30,
              ),
              title: Text("Weather", style: Theme.of(context).textTheme.headline5),
              onTap: () => {Navigator.pushNamed(context, "/weather")},
            ),

            ListTile(
                minVerticalPadding: 20,
                onTap: () => {Navigator.pushNamed(context, "/flightLogs")},
                leading: const Icon(
                  Icons.menu_book,
                  size: 30,
                ),
                title: Text("Log", style: Theme.of(context).textTheme.headline5)),

            Divider(height: 20, thickness: 1, color: Colors.grey.shade700),

            ListTile(
                minVerticalPadding: 20,
                onTap: () => {Navigator.pushNamed(context, "/settings")},
                leading: const Icon(
                  Icons.settings,
                  size: 30,
                ),
                title: Text("Settings", style: Theme.of(context).textTheme.headline5)),

            ListTile(
              minVerticalPadding: 20,
              onTap: () => {Navigator.pushNamed(context, "/about")},
              leading: const Icon(Icons.info, size: 30),
              title: Text("About", style: Theme.of(context).textTheme.headline5),
            )
          ],
        )),
        body: Container(
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
                          plugins: [
                            DragMarkerPlugin(),
                          ],
                        ),
                        layers: [
                          settings.getMapTileLayer(settings.curMapTiles),

                          if (settings.showAirspace && settings.curMapTiles == "topo")
                            TileLayerOptions(
                              urlTemplate:
                                  'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airports@EPSG%3A900913@png/{z}/{x}/{y}.png',
                              maxZoom: 17,
                              tms: true,
                              subdomains: ['1', '2'],
                              backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                            ),
                          if (settings.showAirspace && settings.curMapTiles == "topo")
                            TileLayerOptions(
                              urlTemplate:
                                  'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airspaces_geometries@EPSG%3A900913@png/{z}/{x}/{y}.png',
                              maxZoom: 17,
                              tms: true,
                              subdomains: ['1', '2'],
                              backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                            ),
                          if (settings.showAirspace && settings.curMapTiles == "topo")
                            TileLayerOptions(
                              urlTemplate:
                                  'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airspaces_labels@EPSG%3A900913@png/{z}/{x}/{y}.png',
                              maxZoom: 17,
                              tms: true,
                              subdomains: ['1', '2'],
                              backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                            ),

                          // Other Pilot path trace
                          PolylineLayerOptions(
                              polylines: Provider.of<Group>(context)
                                  .pilots
                                  // Don't see locations older than 10minutes
                                  .values
                                  .where((_p) => _p.geo.time > DateTime.now().millisecondsSinceEpoch - 10000 * 60)
                                  .toList()
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
                                    points: e.latlng, strokeWidth: 6, color: e.getColor(), isDotted: e.isOptional))
                                .toList(),
                          ),

                          // Polyline Directional Barbs
                          MarkerLayerOptions(
                              markers: makePathBarbs(
                                  editingIndex != null
                                      ? (plan.waypoints.toList()
                                        ..removeAt(editingIndex!)
                                        ..add(Waypoint(plan.waypoints[editingIndex!].name, editablePolyline.points,
                                            false, null, plan.waypoints[editingIndex!].color)))
                                      : plan.waypoints,
                                  Provider.of<ActivePlan>(context).isReversed,
                                  45)),

                          // Flight plan markers
                          DragMarkerPluginOptions(
                            markers: plan.waypoints
                                .mapIndexed((i, e) => e.latlng.length == 1
                                    ? DragMarker(
                                        point: e.latlng[0],
                                        height: 60 * 0.8,
                                        width: 40 * 0.8,
                                        updateMapNearEdge: true,
                                        offset: const Offset(0, -30 * 0.8),
                                        feedbackOffset: const Offset(0, -30 * 0.8),
                                        onTap: (_) => plan.selectWaypoint(i),
                                        onDragEnd: (p0, p1) => {
                                              plan.moveWaypoint(i, [p1])
                                            },
                                        builder: (context) => Container(
                                            transformAlignment: const Alignment(0, 0),
                                            transform: Matrix4.rotationZ(-mapController.rotation * pi / 180),
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
                                                  child: e.getIcon(myTelemetry.geo),
                                                  transform:
                                                      Matrix4.rotationZ((mapController.rotation + e.hdg) * pi / 180),
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
                                                        TextSpan(
                                                          text: printValue(
                                                              value: convertDistValueFine(settings.displayUnitsDist,
                                                                  (e.alt - myTelemetry.geo.alt).abs()),
                                                              digits: 5,
                                                              decimals: 0),
                                                          style: const TextStyle(color: Colors.black),
                                                        ),
                                                        TextSpan(
                                                            text: unitStrDistFine[settings.displayUnitsDist],
                                                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12))
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
                                .pilots
                                // Don't see locations older than 10minutes
                                .values
                                .where((_p) => _p.geo.time > DateTime.now().millisecondsSinceEpoch - 10000 * 60)
                                .toList()
                                .map((pilot) => Marker(
                                    point: pilot.geo.latLng,
                                    width: 40,
                                    height: 40,
                                    builder: (ctx) => Container(
                                        transformAlignment: const Alignment(0, 0),
                                        transform: Matrix4.rotationZ(-mapController.rotation * pi / 180),
                                        child: PilotMarker(
                                          pilot,
                                          20,
                                          hdg: pilot.geo.hdg + mapController.rotation * pi / 180,
                                          relAlt: pilot.geo.alt - myTelemetry.geo.alt,
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
                                  child: Image.asset("assets/images/red_arrow.png"),
                                  transform: Matrix4.rotationZ(myTelemetry.geo.hdg),
                                ),
                              ),
                            ],
                          ),

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
                                .pilots
                                .values
                                .where((_p) => _p.geo.time > DateTime.now().millisecondsSinceEpoch - 10000 * 60)
                                .where((e) => !markerIsInView(e.geo.latLng))
                                .map((e) => Builder(builder: (context) {
                                      final theta = (latlngCalc.bearing(mapController.center, e.geo.latLng) +
                                              mapController.rotation -
                                              90) *
                                          pi /
                                          180;
                                      final hypo = MediaQuery.of(context).size.width * 0.8 - 40;
                                      final dist = latlngCalc.distance(mapController.center, e.geo.latLng);

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
                                                      TextSpan(children: [
                                                        TextSpan(
                                                            style: const TextStyle(color: Colors.black, fontSize: 18),
                                                            text: printValue(
                                                                value: convertDistValueCoarse(
                                                                    Provider.of<Settings>(context, listen: false)
                                                                        .displayUnitsDist,
                                                                    dist),
                                                                digits: 4,
                                                                decimals: 1)),
                                                        TextSpan(
                                                            style: const TextStyle(color: Colors.black87, fontSize: 14),
                                                            text: unitStrDistCoarse[
                                                                Provider.of<Settings>(context, listen: false)
                                                                    .displayUnitsDist]),
                                                      ]),
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
                  const numSeconds = 10;
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
              if (focusMode == FocusMode.addWaypoint)
                Positioned(
                  bottom: 15,
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
                        style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                        // textAlign: TextAlign.justify,
                      ),
                    ),
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
                            var _tmp = editablePolyline.points.toList();
                            editablePolyline.points.clear();
                            editablePolyline.points.addAll(_tmp.reversed);
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
                      if (editablePolyline.points.length > 1)
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
                            if (editingIndex == null) {
                              var _temp = Waypoint("", editablePolyline.points.toList(), false, null, null);
                              editWaypoint(context, _temp, isNew: focusMode == FocusMode.addPath)?.then((newWaypoint) {
                                if (newWaypoint != null) {
                                  plan.insertWaypoint(plan.waypoints.length, newWaypoint.name, newWaypoint.latlng,
                                      false, newWaypoint.icon, newWaypoint.color);
                                }
                              });
                            } else {
                              plan.waypoints[editingIndex!].latlng = editablePolyline.points.toList();
                              editingIndex = null;
                            }
                            setFocusMode(prevFocusMode);
                          },
                        ),
                    ],
                  ),
                ),

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
                            child: SvgPicture.asset("assets/images/icon_controls_centermap_me.svg"),
                            onPressed: () =>
                                setFocusMode(FocusMode.me, Provider.of<MyTelemetry>(context, listen: false).geo.latLng),
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
                            lastMapChange = DateTime.now();
                          },
                          child: SvgPicture.asset("assets/images/icon_controls_zoom_out.svg"),
                        ),
                      ]),
                      // --- Chat button
                      Stack(
                        children: [
                          MapButton(
                            size: 60,
                            selected: false,
                            onPressed: () {
                              Navigator.pushNamed(context, "/chat");
                            },
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
                                        color: Colors.red, borderRadius: BorderRadius.all(Radius.circular(10))),
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

              /// Wind direction indicator
              if (Provider.of<Wind>(context).result != null)
                StreamBuilder(
                  stream: mapController.mapEventStream,
                  builder: (context, event) => Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Container(
                          transformAlignment: const Alignment(0, 0),
                          transform: mapReady
                              ? Matrix4.rotationZ(
                                  mapController.rotation * pi / 180 + Provider.of<Wind>(context).result!.windHdg)
                              : Matrix4.rotationZ(0),
                          child: SvgPicture.asset(
                            "assets/images/arrow.svg",
                            width: 80,
                            height: 80,
                            // color: Colors.blue,
                          ),
                        ),
                      )),
                ),
              if (Provider.of<Wind>(context).result != null)
                Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(42),
                      child: Text(
                        printValue(
                            value: convertSpeedValue(Provider.of<Settings>(context, listen: false).displayUnitsSpeed,
                                Provider.of<Wind>(context).result!.windSpd),
                            digits: 2,
                            decimals: 0),
                        style: const TextStyle(color: Colors.black),
                      ),
                    )),

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
                        )))
            ]),
          ),
        ),

        // --- Bottom Instruments
        bottomNavigationBar: Consumer2<ActivePlan, MyTelemetry>(builder: (context, activePlan, myTelemetry, child) {
          ETA etaNext = activePlan.selectedIndex != null
              ? activePlan.etaToWaypoint(myTelemetry.geo, myTelemetry.geo.spd, activePlan.selectedIndex!)
              : ETA(0, 0);

          int etaTime = min(999 * 60000, etaNext.time);

          final curWp = activePlan.selectedWp;

          return Container(
            color: Theme.of(context).backgroundColor,
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // --- Previous Waypoint
                  IconButton(
                    onPressed: () {
                      final wp = activePlan.isReversed ? activePlan.findNextWaypoint() : activePlan.findPrevWaypoint();
                      if (wp != null) activePlan.selectWaypoint(wp);
                    },
                    iconSize: 40,
                    color: (activePlan.selectedIndex != null && activePlan.selectedIndex! > 0)
                        ? Colors.white
                        : Colors.grey.shade700,
                    icon: SvgPicture.asset(
                      "assets/images/reverse_back.svg",
                      color: ((activePlan.isReversed ? activePlan.findNextWaypoint() : activePlan.findPrevWaypoint()) !=
                              null)
                          ? Colors.white
                          : Colors.grey.shade700,
                    ),
                  ),

                  // --- Next Waypoint Info
                  Expanded(
                    child: GestureDetector(
                      onPanDown: (_) => showFlightPlan(),
                      // onTap: showFlightPlan,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 60),
                        color: Theme.of(context).backgroundColor,
                        child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: (curWp != null)
                                  ? [
                                      // --- Current Waypoint Label
                                      // RichText(
                                      Text.rich(
                                        TextSpan(children: [
                                          WidgetSpan(
                                            child: SizedBox(width: 20, height: 30, child: MapMarker(curWp, 30)),
                                          ),
                                          const TextSpan(text: "  "),
                                          TextSpan(
                                            text: curWp.name,
                                            style: const TextStyle(color: Colors.white, fontSize: 30),
                                          ),
                                        ]),
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(
                                        width: MediaQuery.of(context).size.width / 2,
                                        child: Divider(
                                          thickness: 1,
                                          height: 8,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      // --- ETA next
                                      Text.rich(
                                        TextSpan(children: [
                                          TextSpan(
                                              text: printValue(
                                                  value: convertDistValueCoarse(
                                                      Provider.of<Settings>(context, listen: false).displayUnitsDist,
                                                      etaNext.distance),
                                                  digits: 4,
                                                  decimals: 1),
                                              style: instrLower),
                                          TextSpan(
                                              text: unitStrDistCoarse[
                                                  Provider.of<Settings>(context, listen: false).displayUnitsDist],
                                              style: instrLabel),
                                          if (myTelemetry.inFlight) const TextSpan(text: "    "),
                                          if (myTelemetry.inFlight)
                                            richHrMin(
                                                milliseconds: etaTime, valueStyle: instrLower, unitStyle: instrLabel),
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
                                    ]
                                  : const [Text("Select Waypoint")],
                            )),
                      ),
                    ),
                  ),
                  // --- Next Waypoint
                  IconButton(
                      onPressed: () {
                        final wp =
                            !activePlan.isReversed ? activePlan.findNextWaypoint() : activePlan.findPrevWaypoint();
                        if (wp != null) activePlan.selectWaypoint(wp);
                      },
                      iconSize: 40,
                      color: (activePlan.selectedIndex != null &&
                              (!activePlan.isReversed
                                      ? activePlan.findNextWaypoint()
                                      : activePlan.findPrevWaypoint()) !=
                                  null)
                          ? Colors.white
                          : Colors.grey.shade700,
                      icon: const Icon(
                        Icons.skip_next,
                      )),
                ],
              ),
            ),
          );
        }));
  }
}
