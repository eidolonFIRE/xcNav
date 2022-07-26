import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
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

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  late final Animation<Color?> animation;
  late final AnimationController controller;

  bool showWaiting = false;

  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;

  @override
  _LoadingScreenState();

  @override
  void initState() {
    super.initState();

    // Enable Blinking text
    Future.delayed(const Duration(seconds: 10), () => showWaiting = true);

    // Blinking text
    controller = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    final CurvedAnimation curve = CurvedAnimation(parent: controller, curve: Curves.ease);
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

    // Check permissions
    checkPermissions();
  }

  void getInitalLocation() {
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

  void checkPermissions() async {
    if ((await Permission.locationWhenInUse.status).isDenied) {
      // --- When in use is not granted!
      final status = await Permission.locationWhenInUse.request();
      if (status.isGranted) {
        if (Platform.isAndroid || (await Permission.locationAlways.request()).isGranted) {
          //Do some stuff
          getInitalLocation();
        } else {
          debugPrint("Location whileInUse now granted, but requst for always denied");
          //Do another stuff
        }
      } else {
        //The user deny the permission
      }
      if (status.isPermanentlyDenied) {
        //When the user previously rejected the permission and select never ask again
        //Open the screen of settings
        debugPrint("Location permissions all denied");
        if (await openAppSettings()) {
          checkPermissions();
        }
      }
    } else {
      //In use is available, check the always in use
      if (!(await Permission.locationAlways.status).isGranted) {
        if (await Permission.locationAlways.request().isGranted) {
          //Do some stuff
          getInitalLocation();
        } else {
          debugPrint("Location whileInUse but request for always failed.");
          //Do another stuff
        }
      } else {
        //previously available, do some stuff or nothing
        debugPrint("All location permissions look good!");
        getInitalLocation();
      }
    }
  }

  Future<Position> _getCurrentPosition() async {
    return await _geolocatorPlatform.getCurrentPosition();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top]);
    return Material(
        child: Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [
        Color.fromARGB(255, 0xC9, 0xFF, 0xFF),
        Color.fromARGB(255, 0x52, 0x9E, 0x9E),
        Color.fromARGB(255, 0x1E, 0x3E, 0x4F),
        Color.fromARGB(255, 0x16, 0x16, 0x2E),
        Color.fromARGB(255, 0x0A, 0x0A, 0x14),
      ], stops: [
        0,
        0.27,
        0.58,
        0.83,
        1
      ], begin: Alignment.topLeft, end: Alignment.bottomRight, transform: GradientRotation(0))),
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
          Padding(
            padding: const EdgeInsets.only(bottom: 80),
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                  left: MediaQuery.of(context).size.width * 0.155,
                  top: MediaQuery.of(context).size.width * 0.525,
                  child: const SizedBox(
                      width: 500, height: 650, child: DashedLine(Color.fromARGB(200, 255, 255, 255), 6))),
              Positioned(
                  left: MediaQuery.of(context).size.width * 0.215,
                  top: MediaQuery.of(context).size.width * 0.235,
                  child: const SizedBox(width: 500, height: 600, child: DashedLine(Colors.red, 8))),
              Positioned(
                  left: MediaQuery.of(context).size.width * 0.475,
                  top: MediaQuery.of(context).size.width * 0.275,
                  child: const SizedBox(
                      width: 500, height: 580, child: DashedLine(Color.fromARGB(200, 255, 255, 255), 6))),
              SvgPicture.asset(
                "assets/images/xcnav.logo.wings.foreground.svg",
                width: MediaQuery.of(context).size.width / 1.5,
                height: MediaQuery.of(context).size.width / 1.5,
              ),
            ]),
          ),
        ],
      ),
    ));
  }
}
