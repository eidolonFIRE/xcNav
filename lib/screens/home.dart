import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_dragmarker/dragmarker.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';
// import 'dart:math' as math;
import 'dart:async';
import 'package:collection/collection.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/flight_plan.dart';
import 'package:xcnav/util/geo.dart';

// widgets
import 'package:xcnav/widgets/waypoint_card.dart';

import 'package:xcnav/fake_path.dart';

// utils
import 'package:xcnav/util/eta.dart';

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

  static TextStyle instrLower = const TextStyle(fontSize: 30);
  static TextStyle instrUpper = const TextStyle(fontSize: 40);
  static TextStyle instrLabel = const TextStyle(
      fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic);

  @override
  _MyHomePageState();

  // void _incrementCounter() {
  //   setState(() {
  //     // This call to setState tells the Flutter framework that something has
  //     // changed in this State, which causes it to rerun the build method below
  //     // so that the display can reflect the updated values. If we changed
  //     // _counter without calling setState(), then the build method would not be
  //     // called again, and so nothing would appear to happen.
  //     _counter++;
  //   });
  // }

  @override
  void initState() {
    super.initState();

    // intialize the controllers
    mapController = MapController();

    FakeFlight fakeFlight = FakeFlight();

    // --- Geo location loop
    Timer timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      // LocationData geo = await location.getLocation();

      LocationData geo = fakeFlight.genFakeLocationFlight();

      Provider.of<MyTelemetry>(context, listen: false).updateGeo(geo);
      // TODO: no null-check
      // TODO: handle group vs unlocked
      if (focusMode == FocusMode.me) {
        LatLng newCenter = LatLng(geo.latitude!, geo.longitude!);
        // TODO: take zoom level into account for unlock
        if (latlngCalc.distance(newCenter, mapController.center) < 1000) {
          mapController.move(newCenter, mapController.zoom);
        } else {
          // break focus lock
          setFocusMode(FocusMode.unlocked);
        }
      }
    });
  }

  setFocusMode(FocusMode mode, [LatLng? center]) {
    setState(() {
      prevFocusMode = focusMode;
      focusMode = mode;
      print("FocusMode = $mode");
      if (mode == FocusMode.me && center != null) {
        mapController.move(center, mapController.zoom);
      }
    });
  }

  beginAddWaypoint() {
    setFocusMode(FocusMode.addWaypoint);
  }

  void onMapTap(BuildContext context, LatLng latlng) {
    print("onMapTap: $latlng");
    if (focusMode == FocusMode.addWaypoint) {
      // open "add waypoint" popup
      setFocusMode(prevFocusMode);

      // --- Add Waypoint Dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Add Waypoint"),
          content: TextField(
            controller: newWaypointName,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "waypoint name",
              border: OutlineInputBorder(),
            ),
            style: TextStyle(fontSize: 20),
          ),
          actions: [
            ElevatedButton.icon(
                label: const Text("Add"),
                onPressed: () {
                  // TODO: marker icon and color options
                  // TODO: validate name
                  if (newWaypointName.text.isNotEmpty) {
                    Provider.of<FlightPlan>(context, listen: false)
                        .addWaypointNew(
                            newWaypointName.text, latlng, false, null, null);
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
  showFlightPlan() {
    print("Show flight plan");
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
                        print("Selected $i");
                        flightPlan.selectWaypoint(i);
                      },
                      onToggleOptional: () {
                        flightPlan.toggleOptional(i);
                      },
                      isSelected: i == flightPlan.selectedIndex,
                    ),
                    onReorder: (oldIndex, newIndex) {
                      print("WP order: $oldIndex --> $newIndex");
                      flightPlan.sortWaypoint(oldIndex, newIndex);
                    },
                  ),
                ),
              ],
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        automaticallyImplyLeading: false,
        // TODO: menu
        leading: IconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(
            Icons.menu,
            color: Colors.grey,
          ),
          onPressed: () => {},
        ),
        title: Consumer<MyTelemetry>(
            builder: (context, myTelementy, child) => Padding(
                  padding: const EdgeInsets.fromLTRB(30, 2, 30, 2),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
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
                        Text.rich(TextSpan(children: [
                          TextSpan(
                            text: (myTelementy.geo.alt * meters2Feet)
                                .toStringAsFixed(0),
                            style: instrUpper,
                          ),
                          TextSpan(text: " ft", style: instrLabel)
                        ])),
                        Text(
                          myTelementy.geo.vario.toStringAsFixed(0),
                          style: instrUpper,
                        ),
                      ]),
                )),
      ),
      body: Center(
        child: Stack(alignment: Alignment.center, children: [
          Consumer<MyTelemetry>(
            builder: (context, myTelemetry, child) => FlutterMap(
              mapController: mapController,
              options: MapOptions(
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
                                Provider.of<FlightPlan>(context, listen: false)
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
        ]),
      ),
      floatingActionButton: Container(
        alignment: Alignment.centerLeft,
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: FloatingActionButton(
                  heroTag: "me",
                  onPressed: () => setFocusMode(
                      FocusMode.me,
                      Provider.of<MyTelemetry>(context, listen: false)
                          .geo
                          .latLng),
                  backgroundColor: const Color.fromARGB(20, 0, 0, 0),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Image.asset(
                        "assets/images/icon_controls_centermap_me.png"),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: FloatingActionButton(
                  heroTag: "group",
                  onPressed: () => setFocusMode(FocusMode.group),
                  backgroundColor: const Color.fromARGB(20, 0, 0, 0),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Image.asset(
                        "assets/images/icon_controls_centermap_group.png"),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: FloatingActionButton(
                  heroTag: "zoom_in",
                  onPressed: () => {
                    mapController.move(
                        mapController.center, mapController.zoom + 1)
                  },
                  backgroundColor: const Color.fromARGB(20, 0, 0, 0),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child:
                        Image.asset("assets/images/icon_controls_zoom_in.png"),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: FloatingActionButton(
                  heroTag: "zoom_out",
                  onPressed: () => {
                    mapController.move(
                        mapController.center, mapController.zoom - 1)
                  },
                  backgroundColor: const Color.fromARGB(20, 0, 0, 0),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child:
                        Image.asset("assets/images/icon_controls_zoom_out.png"),
                  ),
                ),
              ),
            ]),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(50, 2, 50, 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("fuel"),
            // const Divider(
            //   thickness: 1,
            //   height: 80,
            // ),

            // --- ETA to next waypoint
            GestureDetector(
                onTap: showFlightPlan,
                child: Consumer2<FlightPlan, MyTelemetry>(
                    builder: (context, flightPlan, myTelemetry, child) {
                  if (flightPlan.selectedIndex != null) {
                    ETA eta = flightPlan.etaToWaypoint(myTelemetry.geo.latLng,
                        myTelemetry.geo.spd, flightPlan.selectedIndex!);
                    return Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "ETA next",
                            style: instrLabel,
                          ),
                          Text(
                            eta.hhmm(),
                            style: instrLower,
                          ),
                          Text.rich(TextSpan(children: [
                            TextSpan(text: eta.miles(), style: instrLower),
                            TextSpan(text: " mi", style: instrLabel)
                          ])),
                        ]);
                  } else {
                    return Text(
                      "Select\nWaypoint",
                      style: instrLabel,
                      textAlign: TextAlign.center,
                    );
                  }
                })),

            // --- Trip Time Remaining
            Consumer2<FlightPlan, MyTelemetry>(
                builder: (context, flightPlan, myTelemetry, child) {
              ETA eta = flightPlan.etaToTripEnd(
                  myTelemetry.geo.spd, flightPlan.selectedIndex ?? 0);
              if (flightPlan.selectedIndex != null)
                eta += flightPlan.etaToWaypoint(myTelemetry.geo.latLng,
                    myTelemetry.geo.spd, flightPlan.selectedIndex!);
              return Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "ETA trip",
                      style: instrLabel,
                    ),
                    Text(
                      eta.hhmm(),
                      style: instrLower,
                    ),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: eta.miles(), style: instrLower),
                      TextSpan(text: " mi", style: instrLabel)
                    ])),
                  ]);
            }),
          ],
        ),
      ),
    );
  }
}
