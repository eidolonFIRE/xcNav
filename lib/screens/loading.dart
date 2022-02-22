import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/profile.dart';

import 'package:xcnav/fake_path.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  final Location location = Location();

  @override
  _LoadingScreenState();

  @override
  void initState() {
    super.initState();

    // TODO: check location permissions

    location.getLocation().then((location) {
      debugPrint("initial location: $location");
      // Provider.of<MyTelemetry>(context, listen: false).updateGeo(location);
      // TODO: revert to real gps
      Provider.of<MyTelemetry>(context, listen: false)
          .updateGeo(fakeGeoToLoc(FakeGeo(-121.2971, 37.6738, 20)));

      // Go to next screen
      if (Provider.of<Profile>(context, listen: false).name == null && false) {
        Navigator.pushReplacementNamed(context, "/home");
      } else {
        Navigator.pushReplacementNamed(context, "/profileEditor");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
        child: Container(
      // color: Colors.blueGrey[900],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(30.0),
            // TODO: animate the paragliders
            child: Image.asset("assets/images/android-chrome-512x512.png"),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Text(
              "xcNav",
              style: TextStyle(fontSize: 60),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text("brought to you by the Bay Area PPG group"),
          ),
        ],
      ),
    ));
  }
}
