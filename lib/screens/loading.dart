import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';
// import 'dart:math' as math;
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:xcnav/providers/my_telemetry.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
// import 'package:xcnav/providers/flight_plan.dart';
// import 'package:xcnav/util/geo.dart';




class LoadingScreen extends StatefulWidget {
  const LoadingScreen({Key? key}) : super(key: key);


  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}




class _LoadingScreenState extends State<LoadingScreen> {

  final Location location = Location();

  @override
  _LoadingScreenState();

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

    // TODO: check location permissions

    

    location.getLocation().then((location) {
      print("initial location: $location");
      Provider.of<MyTelemetry>(context, listen: false).updateGeo(location);
      Navigator.pushNamed(context, "/home");
    });

    

  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Container(
        color: Colors.grey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.asset("assets/images/android-chrome-512x512.png"),
            ),
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text("brought to you by the Bay Area PPG group"),
            ),
          ],
        ),
      )
    );
  }
}
