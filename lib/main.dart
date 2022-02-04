import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';
import 'package:wakelock/wakelock.dart';
// import 'dart:math' as math;
import 'dart:async';


import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/top_instrument.dart';



void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MyTelemetry()),
      ],
      child: const MyApp()
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xcNav',
      theme: ThemeData(
        fontFamily: "roboto-condensed",

        // primaryColor: Color.fromRGBO(48, 57, 68, 1),
        // primaryColorLight: Color.fromRGBO(48, 57, 68, 1),
        primarySwatch: Colors.blueGrey,
        brightness: Brightness.dark,
        primaryColorBrightness: Brightness.dark,
      ),

      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // int _counter = 0;
  late MapController mapController;
  final Location location = Location();

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

  // void locationUpdate(BuildContext context, bg.Location location) {
  //   Provider.of<MyTelemetry>(context, listen: false).updateGeo(location);
  //   mapController.move(LatLng(location.coords.latitude, location.coords.longitude), mapController.zoom);
  // }

  @override
  void initState() {
    super.initState();

    Wakelock.enable();

    // intialize the controllers
    mapController = MapController();

    Timer timer = Timer.periodic(const Duration(seconds: 10), (timer) async {
        LocationData geo = await location.getLocation();
        Provider.of<MyTelemetry>(context, listen: false).updateGeo(geo);
        // TODO: no null-check
        mapController.move(LatLng(geo.latitude!, geo.longitude!), mapController.zoom);
    });

  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Consumer<MyTelemetry>(
          builder: (context, myTelementy, child) =>  
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TopInstrument(value: myTelementy.geo.spd.toStringAsFixed(0)),
                TopInstrument(value: myTelementy.geo.alt.toStringAsFixed(0)),
                TopInstrument(value: myTelementy.geo.vario.toStringAsFixed(0)),
              ])
          ),
      ),

      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child:
          // Map box
          Consumer<MyTelemetry>(builder: (context, myTelemetry, child) => 
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                center: LatLng(37, -122),
                zoom: 12.0,
              ),
              layers: [
                TileLayerOptions(
                  // urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                  // subdomains: ['a', 'b', 'c'],
                  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
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
                      builder: (ctx) =>
                      
                      Container(
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
        ),

      floatingActionButton: Container(
        alignment: Alignment.centerLeft, 
        child: FloatingActionButton(onPressed: () => {}),
      ),

      bottomNavigationBar: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly
        ,
        children: [
          TopInstrument(value: "1"),
          TopInstrument(value: "2"),
          TopInstrument(value: "3"),
        ],
      )
    );
  }
}
