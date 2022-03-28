import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

class _LoadingScreenState extends State<LoadingScreen> {
  final Location location = Location();

  final TextStyle _contributerStyle = const TextStyle(fontSize: 18);

  @override
  _LoadingScreenState();

  @override
  void initState() {
    super.initState();

    // TODO: check location permissions

    location.getLocation().then((location) {
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

  @override
  Widget build(BuildContext context) {
    return Material(
        child: Container(
      // color: Colors.blueGrey[900],
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
