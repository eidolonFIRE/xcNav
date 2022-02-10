import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
import 'package:xcnav/widgets/top_instrument.dart';
import 'package:xcnav/widgets/waypoint_card.dart';

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

  // TODO: move this to utils
  static var calc = const Distance(roundResult: false);

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

    // --- Geo location loop
    Timer timer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      LocationData geo = await location.getLocation();
      Provider.of<MyTelemetry>(context, listen: false).updateGeo(geo);
      // TODO: no null-check
      // TODO: handle group vs unlocked
      if (focusMode == FocusMode.me) {
        LatLng newCenter = LatLng(geo.latitude!, geo.longitude!);
        // TODO: take zoom level into account for unlock
        if (calc.distance(newCenter, mapController.center) > 100) {
          mapController.move(newCenter, mapController.zoom);
        } else {
          // break focus lock
          setFocusMode(FocusMode.unlocked);
        }
      }
    });
  }

  setFocusMode(FocusMode mode, [LatLng? center]) {
    prevFocusMode = focusMode;
    focusMode = mode;
    print("FocusMode = $mode");
    if (mode == FocusMode.me && center != null) {
      mapController.move(center, mapController.zoom);
    }
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
          title: const Text("Add Waypoint"),
          content: const TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: "waypoint name",
              border: OutlineInputBorder(),
            ),
            style: TextStyle(fontSize: 20),
          ),
          actions: [
            ElevatedButton.icon(
                label: const Text("Add"),
                onPressed: () {
                  Provider.of<FlightPlan>(context, listen: false)
                      .addWaypointNew("new", latlng, false);
                  Navigator.pop(context);
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
        title: Consumer<MyTelemetry>(
            builder: (context, myTelementy, child) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TopInstrument(
                          value: myTelementy.geo.spd.toStringAsFixed(0)),
                      TopInstrument(
                          value: myTelementy.geo.alt.toStringAsFixed(0)),
                      TopInstrument(
                          value: myTelementy.geo.vario.toStringAsFixed(0)),
                    ])),
      ),
      body: Center(
        child: Consumer<MyTelemetry>(
          builder: (context, myTelemetry, child) => FlutterMap(
            mapController: mapController,
            options: MapOptions(
              center: myTelemetry.geo.latLng,
              zoom: 12.0,
              onTap: (tapPosition, point) => onMapTap(context, point),
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

              // Flight plan markers
              MarkerLayerOptions(
                // TODO: investigate using stream<> here
                markers: Provider.of<FlightPlan>(context)
                    .waypoints
                    .map((e) => Marker(
                        // TODO: support lines
                        point: e.latlng[0],
                        // TODO: get this alignment correct (it's slightly off)
                        anchorPos: AnchorPos.align(AnchorAlign.top),
                        builder: (context) => const Icon(Icons.location_on,
                            size: 50, color: Colors.black)))
                    .toList(),
              ),

              // Trip snake lines
              PolylineLayerOptions(
                  polylines: Provider.of<FlightPlan>(context).buildTripSnake())
            ],
          ),
        ),
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
      bottomNavigationBar: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TopInstrument(value: "fuel"),
          const Divider(
            thickness: 1,
          ),
          TextButton(onPressed: showFlightPlan, child: Text("ETA next")),
          TopInstrument(value: "ETA trip"),
        ],
      ),
    );
  }
}
