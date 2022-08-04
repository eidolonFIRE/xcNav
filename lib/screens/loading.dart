import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/util.dart';

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

  bool checked = false;
  bool failedPerms = false;

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
  }

  void getInitalLocation() {
    // get initial location
    debugPrint("Getting initial location from GPS");
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

  void checkPermissions(BuildContext context) async {
    if (checked) {
      debugPrint("Skipping location permission check...");
      return;
    }

    Timer(const Duration(seconds: 5), () => checked = false);
    checked = true;

    debugPrint("Checking location permissions...");
    final whenInUse = await Permission.locationWhenInUse.status;
    if (whenInUse.isPermanentlyDenied) {
      failedPerms = true;
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
                content: Text(Platform.isIOS
                    ? "Please set location permission to \"always\""
                    : "Please enable location permission"),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.lightGreen),
                    onPressed: () {
                      Navigator.pop(context);
                      openAppSettings();
                    },
                  )
                ],
              ));
      return;
    } else if (whenInUse.isDenied) {
      debugPrint("Location whenInUse was not granted!");
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        failedPerms = true;
        return;
      }
    }

    if (Platform.isIOS) {
      // --- Check "always"
      final locAlways = await Permission.locationAlways.status;
      if (locAlways.isPermanentlyDenied) {
        failedPerms = true;
        showDialog(
            context: context,
            builder: (context) => AlertDialog(
                  content: Text(Platform.isIOS
                      ? "Please set location permission to \"always\""
                      : "Please enable location permission"),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.lightGreen),
                      onPressed: () {
                        Navigator.pop(context);
                        openAppSettings();
                      },
                    )
                  ],
                ));
        return;
      } else if (!locAlways.isGranted) {
        debugPrint("Location always was not granted!");
        final status = await Permission.locationAlways.request();
        if (!status.isGranted) {
          failedPerms = true;
          return;
        }
      }
    }

    failedPerms = false;
    debugPrint("Location permissions all look good!");
    getInitalLocation();
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
    setSystemUI();

    checkPermissions(context);

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
          if (showWaiting && failedPerms && checked)
            Text(
              "Check location permission${Platform.isIOS ? " is set to ALWAYS." : "."}",
              softWrap: true,
              maxLines: 2,
              style: const TextStyle(color: Colors.redAccent, fontSize: 20),
            ),
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
