import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xcnav/endpoint.dart';

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
  DateTime lastChecked = DateTime.fromMillisecondsSinceEpoch(0);
  bool failedPerms = false;

  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;

  bool get checkedRecently => lastChecked.isAfter(DateTime.now().subtract(const Duration(seconds: 5)));

  late final Timer showWaitingTimer;

  @override
  _LoadingScreenState();

  @override
  void initState() {
    super.initState();

    // Enable Blinking text
    showWaitingTimer = Timer(const Duration(seconds: 10), () => showWaiting = true);

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
    _geolocatorPlatform.getCurrentPosition().then((location) {
      debugPrint("initial location: $location");
      Provider.of<MyTelemetry>(context, listen: false).init();
      Provider.of<MyTelemetry>(context, listen: false).updateGeo(location);

      // Setup the backend
      selectEndpoint(LatLng(location.latitude, location.longitude));

      // Go to next screen
      final name = Provider.of<Profile>(context, listen: false).name;
      if (name != null && name.length >= 2) {
        Navigator.pushReplacementNamed(context, "/home");
      } else {
        Navigator.pushReplacementNamed(context, "/profileEditor");
      }
    });
  }

  void checkPermissions(BuildContext context) async {
    if (Platform.isIOS) {
      Permission.camera.request();
      Permission.photos.request();
    }

    if (checkedRecently) {
      return;
    } else {
      lastChecked = DateTime.now();
    }

    debugPrint("Checking location permissions...");
    final whenInUse = await Permission.locationWhenInUse.status;
    if (whenInUse.isPermanentlyDenied) {
      debugPrint("Location was fully denied!");
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
        debugPrint("Location was fully denied!");
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
        debugPrint("Location-always was not granted!");
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

  @override
  void dispose() {
    controller.dispose();
    showWaitingTimer.cancel();
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(),
          // --- Header Text
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: SvgPicture.asset(
              "assets/images/xcnav.logo.type.svg",
              width: MediaQuery.of(context).size.width / 3.5,
              height: MediaQuery.of(context).size.width / 2.5,
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
          if (showWaiting && failedPerms && !checkedRecently)
            Text(
              "Check location permission${Platform.isIOS ? " is set to ALWAYS." : "."}",
              softWrap: true,
              maxLines: 2,
              style: const TextStyle(color: Colors.redAccent, fontSize: 20),
            ),
          // --- Wings and Dashed lines
          SizedBox(
            // padding: const EdgeInsets.only(bottom: 80),
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height / 2.5,
            child: Stack(fit: StackFit.expand, clipBehavior: Clip.hardEdge, children: [
              Positioned(
                  left: MediaQuery.of(context).size.width * (0.155 + 0.13),
                  top: MediaQuery.of(context).size.width * 0.525,
                  child: const SizedBox(
                      width: 500, height: 650, child: DashedLine(Color.fromARGB(200, 255, 255, 255), 6))),
              Positioned(
                  left: MediaQuery.of(context).size.width * (0.215 + 0.13),
                  top: MediaQuery.of(context).size.width * 0.235,
                  child: const SizedBox(width: 500, height: 600, child: DashedLine(Colors.red, 8))),
              Positioned(
                  left: MediaQuery.of(context).size.width * (0.475 + 0.13),
                  top: MediaQuery.of(context).size.width * 0.275,
                  child: const SizedBox(
                      width: 500, height: 580, child: DashedLine(Color.fromARGB(200, 255, 255, 255), 6))),
              Positioned(
                left: MediaQuery.of(context).size.width * 0.13,
                top: 0,
                child: SvgPicture.asset(
                  "assets/images/xcnav.logo.wings.foreground.svg",
                  width: MediaQuery.of(context).size.width / 1.5,
                  height: MediaQuery.of(context).size.width / 1.5,
                ),
              ),
            ]),
          ),
        ],
      ),
    ));
  }
}
