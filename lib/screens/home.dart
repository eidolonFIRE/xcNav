import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_dragmarker/dragmarker.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/flight_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/widgets/map_button.dart';

// widgets
import 'package:xcnav/widgets/waypoint_card.dart';
import 'package:xcnav/widgets/avatar_round.dart';

import 'package:xcnav/fake_path.dart';

// models
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';

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
}

class _MyHomePageState extends State<MyHomePage> {
  // int _counter = 0;
  late MapController mapController;
  final Location location = Location();
  FocusMode focusMode = FocusMode.me;
  FocusMode prevFocusMode = FocusMode.me;

  final TextEditingController newWaypointName = TextEditingController();

  static TextStyle instrLower = const TextStyle(fontSize: 35);
  static TextStyle instrUpper = const TextStyle(fontSize: 50);
  static TextStyle instrLabel = const TextStyle(
      fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic);

  @override
  _MyHomePageState();

  @override
  void initState() {
    super.initState();

    // intialize the controllers
    mapController = MapController();

    FakeFlight fakeFlight = FakeFlight();

    // --- Geo location loop
    // Timer timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
    //   // LocationData geo = await location.getLocation();

    //   LocationData geo = fakeFlight.genFakeLocationFlight();

    //   Provider.of<MyTelemetry>(context, listen: false).updateGeo(geo);
    //   // TODO: no null-check
    //   // TODO: handle group vs unlocked
    //   if (focusMode == FocusMode.me) {
    //     LatLng newCenter = LatLng(geo.latitude!, geo.longitude!);
    //     // TODO: take zoom level into account for unlock
    //     if (latlngCalc.distance(newCenter, mapController.center) < 1000) {
    //       mapController.move(newCenter, mapController.zoom);
    //     } else {
    //       // break focus lock
    //       setFocusMode(FocusMode.unlocked);
    //     }
    //   }
    // });
  }

  void setFocusMode(FocusMode mode, [LatLng? center]) {
    setState(() {
      prevFocusMode = focusMode;
      focusMode = mode;
      debugPrint("FocusMode = $mode");
      if (mode == FocusMode.me && center != null) {
        mapController.move(center, mapController.zoom);
      }
    });
  }

  void beginAddWaypoint() {
    setFocusMode(FocusMode.addWaypoint);
  }

  void onMapTap(BuildContext context, LatLng latlng) {
    debugPrint("onMapTap: $latlng");
    if (focusMode == FocusMode.addWaypoint) {
      // open "add waypoint" popup
      setFocusMode(prevFocusMode);

      // --- Add Waypoint Dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Add Waypoint"),
          content: TextField(
            controller: newWaypointName,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "waypoint name",
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 20),
          ),
          actions: [
            ElevatedButton.icon(
                label: const Text("Add"),
                onPressed: () {
                  // TODO: marker icon and color options
                  // TODO: validate name
                  if (newWaypointName.text.isNotEmpty) {
                    Provider.of<FlightPlan>(context, listen: false)
                        .insertWaypoint(null, newWaypointName.text, latlng,
                            false, null, null);
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(
                  Icons.check,
                  size: 20,
                  color: Colors.lightGreen,
                )),
            ElevatedButton.icon(
                label: const Text("Cancel"),
                onPressed: () => {Navigator.pop(context)},
                icon: const Icon(
                  Icons.cancel,
                  size: 20,
                  color: Colors.red,
                )),
          ],
        ),
      );
    }
  }

  // --- Flight Plan Menu
  void showFlightPlan() {
    debugPrint("Show flight plan");
    // TODO: move map view to see whole flight plan
    showModalBottomSheet(
        context: context,
        elevation: 0,
        constraints: const BoxConstraints(maxHeight: 400),
        builder: (BuildContext context) {
          return Consumer<FlightPlan>(
            builder: (context, flightPlan, child) => Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                          beginAddWaypoint();
                        },
                        icon: const Icon(Icons.add,
                            size: 20, color: Colors.lightGreen)),
                    IconButton(
                        onPressed: () => {},
                        icon: const Icon(
                          Icons.upload,
                          size: 20,
                        )),
                    IconButton(
                        onPressed: () => flightPlan.removeSelectedWaypoint(),
                        icon: const Icon(Icons.delete,
                            size: 20, color: Colors.red)),
                  ],
                ),
                SizedBox(
                  height: 300,
                  child: ReorderableListView.builder(
                    itemCount: flightPlan.waypoints.length,
                    itemBuilder: (context, i) => WaypointCard(
                      key: ValueKey(flightPlan.waypoints[i]),
                      waypoint: flightPlan.waypoints[i],
                      index: i,
                      onSelect: () {
                        debugPrint("Selected $i");
                        flightPlan.selectWaypoint(i);
                      },
                      onToggleOptional: () {
                        flightPlan.toggleOptional(i);
                      },
                      isSelected: i == flightPlan.selectedIndex,
                    ),
                    onReorder: (oldIndex, newIndex) {
                      debugPrint("WP order: $oldIndex --> $newIndex");
                      flightPlan.sortWaypoint(oldIndex, newIndex);
                    },
                  ),
                ),
              ],
            ),
          );
        });
  }

  // --- Fuel Level Editor Dialog
  void showFuelDialog() {
    showDialog(
        context: context,
        builder: (context) {
          TextStyle numbers = const TextStyle(fontSize: 40);

          return Consumer<MyTelemetry>(builder: (context, myTelemetry, child) {
            return AlertDialog(
              title: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: const [
                  Text("Fuel Level"),
                  Text("Burn Rate"),
                ],
              ),
              content: Row(
                children: [
                  // --- Fuel Level
                  Card(
                    color: Colors.grey.shade700,
                    child: Row(children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              onPressed: () => {myTelemetry.updateFuel(1)},
                              icon: const Icon(
                                Icons.keyboard_arrow_up,
                                color: Colors.lightGreen,
                              )),
                          Text(
                            myTelemetry.fuel.floor().toString(),
                            style: numbers,
                            textAlign: TextAlign.center,
                          ),
                          IconButton(
                              onPressed: () => {myTelemetry.updateFuel(-1)},
                              icon: const Icon(
                                Icons.keyboard_arrow_down,
                                color: Colors.red,
                              )),
                        ],
                      ),
                      Text(
                        ".",
                        style: numbers,
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            onPressed: () => {myTelemetry.updateFuel(0.1)},
                            icon: const Icon(
                              Icons.keyboard_arrow_up,
                              color: Colors.lightGreen,
                            )),
                        Text(
                          ((myTelemetry.fuel % 1) * 10).floor().toString(),
                          style: numbers,
                          textAlign: TextAlign.center,
                        ),
                        IconButton(
                            onPressed: () => {myTelemetry.updateFuel(-0.1)},
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.red,
                            )),
                      ])
                    ]),
                  ),

                  // --- Burn Rate
                  Card(
                    color: Colors.grey.shade700,
                    child: Row(children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              onPressed: () =>
                                  {myTelemetry.updateFuelBurnRate(1)},
                              icon: const Icon(
                                Icons.keyboard_arrow_up,
                                color: Colors.lightGreen,
                              )),
                          Text(
                            myTelemetry.fuelBurnRate.floor().toString(),
                            style: numbers,
                            textAlign: TextAlign.center,
                          ),
                          IconButton(
                              onPressed: () =>
                                  {myTelemetry.updateFuelBurnRate(-1)},
                              icon: const Icon(
                                Icons.keyboard_arrow_down,
                                color: Colors.red,
                              )),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(1, 6, 1, 0),
                        child: Text(
                          ".",
                          style: numbers,
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            onPressed: () =>
                                {myTelemetry.updateFuelBurnRate(0.1)},
                            icon: const Icon(
                              Icons.keyboard_arrow_up,
                              color: Colors.lightGreen,
                            )),
                        Text(
                          ((myTelemetry.fuelBurnRate % 1) * 10)
                              .floor()
                              .toString(),
                          style: numbers,
                          textAlign: TextAlign.center,
                        ),
                        IconButton(
                            onPressed: () =>
                                {myTelemetry.updateFuelBurnRate(-0.1)},
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.red,
                            )),
                      ])
                    ]),
                  )
                ],
              ),
              // actions: [
              //   ElevatedButton.icon(
              //       label: const Text("Update"),
              //       onPressed: () {
              //         Navigator.pop(context);
              //       },
              //       icon: const Icon(
              //         Icons.check,
              //         size: 20,
              //         color: Colors.lightGreen,
              //       )),
              //   ElevatedButton.icon(
              //       label: const Text("Cancel"),
              //       onPressed: () => {Navigator.pop(context)},
              //       icon: const Icon(
              //         Icons.cancel,
              //         size: 20,
              //         color: Colors.red,
              //       )),
              // ],
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
          // TODO: menu
          leadingWidth: 35,
          // leading: IconButton(
          //   padding: EdgeInsets.zero,
          //   icon: const Icon(
          //     Icons.menu,
          //     color: Colors.grey,
          //   ),
          //   onPressed: () => {},
          // ),
          title: Consumer<MyTelemetry>(
              builder: (context, myTelementy, child) => Padding(
                    padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // --- Speedometer
                          Text.rich(TextSpan(children: [
                            TextSpan(
                              text: (myTelementy.geo.spd * 3.6 * km2Miles)
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
                          // TODO: replace with graphic
                          Text(
                            myTelementy.geo.vario.toStringAsFixed(1),
                            style: instrUpper,
                          ),
                        ]),
                  )),
        ),
        drawer: Drawer(
            child: ListView(
          children: [
            SizedBox(
              height: 120,
              child: DrawerHeader(
                  child: Stack(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    AvatarRound(Provider.of<Profile>(context).avatar, 40),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        Provider.of<Profile>(context).name ?? "unset",
                        style: TextStyle(fontSize: 30),
                      ),
                    ),
                  ],
                ),
                Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton(
                      iconSize: 20,
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        Navigator.pushNamed(context, "/profileEditor");
                      },
                    ))
              ])),
            ),
            // Map tile-layer selection

            TextButton.icon(
                onPressed: () => {},
                icon: const Icon(
                  Icons.flight_takeoff,
                  size: 30,
                ),
                label: const Text("Flight Log")),
            TextButton.icon(
                onPressed: () => {},
                icon: const Icon(
                  Icons.settings,
                  size: 30,
                ),
                label: const Text("Settings")),

            // Settings
            // - update profile
            // - units
            // - gps frequency?
            // - debug controls
          ],
        )),
        body: Center(
          child: Stack(alignment: Alignment.center, children: [
            Consumer<MyTelemetry>(
              builder: (context, myTelemetry, child) => FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  interactiveFlags:
                      InteractiveFlag.all & ~InteractiveFlag.rotate,
                  center: myTelemetry.geo.latLng,
                  zoom: 12.0,
                  onTap: (tapPosition, point) => onMapTap(context, point),
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
                  // TODO: re-enable airspace layers
                  // TileLayerOptions(
                  //   urlTemplate: 'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airports@EPSG%3A900913@png/{z}/{x}/{y}.png',
                  //   maxZoom: 17,
                  //   tms: true,
                  //   subdomains: ['1','2'],
                  //   backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                  // ),
                  // TileLayerOptions(
                  //   urlTemplate: 'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airspaces_geometries@EPSG%3A900913@png/{z}/{x}/{y}.png',
                  //   maxZoom: 17,
                  //   tms: true,
                  //   subdomains: ['1','2'],
                  //   backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                  // ),
                  // TileLayerOptions(
                  //   urlTemplate: 'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airspaces_labels@EPSG%3A900913@png/{z}/{x}/{y}.png',
                  //   maxZoom: 17,
                  //   tms: true,
                  //   subdomains: ['1','2'],
                  //   backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                  // ),

                  // Flight Log
                  PolylineLayerOptions(
                      polylines: [myTelemetry.buildFlightTrace()]),

                  // Trip snake lines
                  PolylineLayerOptions(
                      polylines:
                          Provider.of<FlightPlan>(context).buildTripSnake()),

                  PolylineLayerOptions(
                    polylines: [
                      Provider.of<FlightPlan>(context)
                          .buildNextWpIndicator(myTelemetry.geo)
                    ],
                  ),

                  // Flight plan markers
                  DragMarkerPluginOptions(
                    // TODO: investigate using stream<> here
                    markers: Provider.of<FlightPlan>(context)
                        .waypoints
                        .mapIndexed((i, e) => DragMarker(
                            // TODO: support lines
                            point: e.latlng[0],
                            height: 60,
                            onDragEnd: (p0, p1) => {
                                  Provider.of<FlightPlan>(context,
                                          listen: false)
                                      .moveWaypoint(i, p1)
                                },
                            builder: (context) => Stack(children: [
                                  Container(
                                    transform:
                                        Matrix4.translationValues(0, -28, 0),
                                    child: Image.asset(
                                      "assets/images/pin.png",
                                      color: e.color == null
                                          ? Colors.black
                                          : Color(e.color!),
                                    ),
                                  ),
                                  Container(
                                    transform:
                                        Matrix4.translationValues(2, -13, 0),
                                    child: const Icon(
                                      // TODO: support other icons
                                      Icons.circle,
                                      size: 24,
                                    ),
                                  ),
                                ])))
                        .toList(),
                  ),

                  // Live locations other pilots
                  MarkerLayerOptions(
                    markers: Provider.of<Group>(context)
                        .pilots
                        .values
                        .toList()
                        .map((pilot) => Marker(
                            point: pilot.geo.latLng,
                            builder: (ctx) => AvatarRound(pilot.avatar, 10)))
                        .toList(),
                  ),

                  // "ME" Live Location Marker
                  MarkerLayerOptions(
                    markers: [
                      Marker(
                        width: 40.0,
                        height: 40.0,
                        point: myTelemetry.geo.latLng,
                        builder: (ctx) => Container(
                          transformAlignment: const Alignment(0, 0),
                          child: Image.asset("assets/images/red_arrow.png"),
                          transform: Matrix4.rotationZ(myTelemetry.geo.hdg),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- Map overlay layers
            if (focusMode == FocusMode.addWaypoint)
              const Positioned(
                bottom: 15,
                child: Text.rich(
                  TextSpan(children: [
                    WidgetSpan(
                        child: Icon(
                      Icons.touch_app,
                      size: 40,
                      color: Colors.black,
                    )),
                    TextSpan(text: "Tap to place waypoint")
                  ]),
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 25,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),

            // --- Map View Buttons
            Positioned(
              left: 0,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(5, 20, 0, 0),
                        child: MapButton(
                          size: 60,
                          child: Image.asset(
                              "assets/images/icon_controls_centermap_me.png"),
                          onPressed: () => setFocusMode(
                              FocusMode.me,
                              Provider.of<MyTelemetry>(context, listen: false)
                                  .geo
                                  .latLng),
                        )),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 30, 0, 20),
                      child: MapButton(
                        size: 60,
                        onPressed: () => setFocusMode(FocusMode.group),
                        child: Image.asset(
                            "assets/images/icon_controls_centermap_group.png"),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 60, 0, 0),
                      child: MapButton(
                        size: 60,
                        onPressed: () => {
                          mapController.move(
                              mapController.center, mapController.zoom + 1)
                        },
                        child: Image.asset(
                            "assets/images/icon_controls_zoom_in.png"),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 30, 0, 20),
                      child: MapButton(
                        size: 60,
                        onPressed: () => {
                          mapController.move(
                              mapController.center, mapController.zoom - 1)
                        },
                        child: Image.asset(
                            "assets/images/icon_controls_zoom_out.png"),
                      ),
                    ),
                  ]),
            ),

            Positioned(
                bottom: 10,
                left: 5,
                child: MapButton(
                  size: 60,
                  onPressed: () => {Navigator.pushNamed(context, "/party")},
                  child: const Icon(
                    Icons.chat,
                    size: 30,
                    color: Colors.black,
                  ),
                )),

            Provider.of<Client>(context).state == ClientState.disconnected
                ? const Positioned(
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
                : Container(),
          ]),
        ),

        // --- Bottom Instruments
        bottomNavigationBar: Consumer2<FlightPlan, MyTelemetry>(
            builder: (context, flightPlan, myTelemetry, child) {
          ETA etaNext = flightPlan.selectedIndex != null
              ? flightPlan.etaToWaypoint(myTelemetry.geo.latLng,
                  myTelemetry.geo.spd, flightPlan.selectedIndex!)
              : ETA(0, 0);
          ETA etaTrip = flightPlan.etaToTripEnd(
              myTelemetry.geo.spd, flightPlan.selectedIndex ?? 0);
          if (flightPlan.selectedIndex != null) {
            etaTrip += flightPlan.etaToWaypoint(myTelemetry.geo.latLng,
                myTelemetry.geo.spd, flightPlan.selectedIndex!);
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(30, 2, 50, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // --- Fuel Indicator
                GestureDetector(
                  onTap: showFuelDialog,
                  child: Card(
                    color: myTelemetry.fuelIndicatorColor(etaNext, etaTrip),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Fuel",
                            style: instrLabel,
                          ),
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: myTelemetry.fuel.toStringAsFixed(1),
                                style: instrLower),
                            TextSpan(text: " L", style: instrLabel)
                          ])),
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: myTelemetry.fuelTimeRemaining(),
                                style: instrLower)
                          ]))
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                    height: 100,
                    child: VerticalDivider(thickness: 2, color: Colors.black)),

                // --- ETA to next waypoint
                GestureDetector(
                    onTap: showFlightPlan,
                    child: (flightPlan.selectedIndex != null)
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                Text(
                                  "ETA next",
                                  style: instrLabel,
                                ),
                                Text.rich(TextSpan(children: [
                                  TextSpan(
                                      text: etaNext.miles(), style: instrLower),
                                  TextSpan(text: " mi", style: instrLabel)
                                ])),
                                Text(
                                  etaNext.hhmm(),
                                  style: instrLower,
                                ),
                              ])
                        : Text(
                            "Select\nWaypoint",
                            style: instrLabel,
                            textAlign: TextAlign.center,
                          )),

                const SizedBox(
                    height: 100,
                    child: VerticalDivider(thickness: 2, color: Colors.black)),

                // --- Trip Time Remaining
                Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "ETA trip",
                        style: instrLabel,
                      ),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: etaTrip.miles(), style: instrLower),
                        TextSpan(text: " mi", style: instrLabel)
                      ])),
                      Text(
                        etaTrip.hhmm(),
                        style: instrLower,
                      ),
                    ])
              ],
            ),
          );
        }));
  }
}
