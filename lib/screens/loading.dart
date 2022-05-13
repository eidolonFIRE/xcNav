import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
// import 'package:permission_handler/permission_handler.dart' as perms;

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/profile.dart';

// widgets
import 'package:xcnav/widgets/dashed_line.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  final TextStyle _contributerStyle = const TextStyle(fontSize: 18);

  late final Animation<Color?> animation;
  late final AnimationController controller;

  bool showWaiting = false;

  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;
  static const String _kLocationServicesDisabledMessage =
      'Location services are disabled.';
  static const String _kPermissionDeniedMessage = 'Permission denied.';
  static const String _kPermissionGrantedMessage = 'Permission granted.';

  @override
  _LoadingScreenState();

  @override
  void initState() {
    super.initState();

    // Enable Blinking text
    Future.delayed(const Duration(seconds: 10), () => showWaiting = true);

    // Blinking text
    controller = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this);
    final CurvedAnimation curve =
        CurvedAnimation(parent: controller, curve: Curves.ease);
    animation = ColorTween(begin: Colors.white, end: Colors.red).animate(curve);
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.reverse();
      } else if (status == AnimationStatus.dismissed) {
        controller.forward();
      }
      setState(() {});
    });
    controller.forward();

    // get initial location
    _getCurrentPosition().then((location) {
      debugPrint("initial location: $location");
      Provider.of<MyTelemetry>(context, listen: false).updateGeo(location);

      // Go to next screen
      if (Provider.of<Profile>(context, listen: false).name != null) {
        Navigator.pushReplacementNamed(context, "/home");
      } else {
        Navigator.pushReplacementNamed(context, "/profileEditor");
      }
    });
  }

  //   Future<bool> _checkPermissions() async {
  //   return (await perms.Permission.location.isGranted) &&
  //       (await perms.Permission.locationWhenInUse.isGranted);
  // }

  Future<Position> _getCurrentPosition() async {
    final hasPermission = await _handlePermission();

    // This shouldn't be happening...
    if (!hasPermission) {
      return Position(
          accuracy: 0,
          longitude: 0,
          latitude: 0,
          altitude: 0,
          speed: 0,
          speedAccuracy: 0,
          heading: 0,
          timestamp: DateTime.now());
    }

    return await _geolocatorPlatform.getCurrentPosition();
  }

  Future<bool> _handlePermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await _geolocatorPlatform.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      debugPrint(_kLocationServicesDisabledMessage);
      return false;
    }

    permission = await _geolocatorPlatform.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocatorPlatform.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        debugPrint(_kPermissionDeniedMessage);
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      debugPrint("_kPermissionDeniedForeverMessage");
      return false;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    debugPrint(_kPermissionGrantedMessage);
    return true;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
        child: Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [
            Color.fromARGB(255, 0xC9, 0xFF, 0xFF),
            Color.fromARGB(255, 0x52, 0x9E, 0x9E),
            Color.fromARGB(255, 0x1E, 0x3E, 0x4F),
            Color.fromARGB(255, 0x16, 0x16, 0x2E),
            Color.fromARGB(255, 0x0A, 0x0A, 0x14),
          ],
              stops: [
            0,
            0.27,
            0.58,
            0.83,
            1
          ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: GradientRotation(0))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // --- Header Text
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: SvgPicture.asset(
              "assets/images/xcnav.logo.type.svg",
              width: MediaQuery.of(context).size.width / 4,
              height: MediaQuery.of(context).size.width / 3,
            ),
          ),
          if (showWaiting)
            AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  return Text(
                    "- Waiting for GPS -",
                    style: TextStyle(fontSize: 30, color: animation.value),
                  );
                }),
          // --- Wings and Dashed lines
          Stack(clipBehavior: Clip.none, children: [
            // SizedBox(
            //   width: MediaQuery.of(context).size.width / 1.5,
            //   height: MediaQuery.of(context).size.width / 1.5,
            //   child: SvgPicture.asset(
            //       "assets/images/xcnav.logo.wings.background.svg"),
            // ),
            Positioned(
                left: MediaQuery.of(context).size.width * 0.155,
                top: MediaQuery.of(context).size.width * 0.525,
                child: const SizedBox(
                    width: 500,
                    height: 650,
                    child: DashedLine(Color.fromARGB(200, 255, 255, 255), 6))),
            Positioned(
                left: MediaQuery.of(context).size.width * 0.215,
                top: MediaQuery.of(context).size.width * 0.235,
                child: const SizedBox(
                    width: 500, height: 600, child: DashedLine(Colors.red, 8))),
            Positioned(
                left: MediaQuery.of(context).size.width * 0.475,
                top: MediaQuery.of(context).size.width * 0.275,
                child: const SizedBox(
                    width: 500,
                    height: 580,
                    child: DashedLine(Color.fromARGB(200, 255, 255, 255), 6))),
            SvgPicture.asset(
              "assets/images/xcnav.logo.wings.foreground.svg",
              width: MediaQuery.of(context).size.width / 1.5,
              height: MediaQuery.of(context).size.width / 1.5,
            ),
          ]),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Contributors",
                style: TextStyle(fontSize: 24),
              ),
              SizedBox(
                  width: MediaQuery.of(context).size.width / 2,
                  child: const Divider(
                    color: Colors.white,
                  )),
              Text(
                "Caleb Johnson",
                style: _contributerStyle,
              ),
              Text(
                "Edwin Veelo",
                style: _contributerStyle,
              ),
            ],
          )
        ],
      ),
    ));
  }
}
