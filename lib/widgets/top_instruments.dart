import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/dialogs/wind_dialog.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';

const topInstrumentsHeight = 90.0;

Widget topInstruments(BuildContext context) {
  const upperStyle = TextStyle(fontSize: 45);
  const lowerStyle = TextStyle(fontSize: 16);
  final TextStyle unitStyle = TextStyle(fontSize: 14, color: Colors.grey.shade400, fontStyle: FontStyle.italic);

  return Padding(
    padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
    child: Container(
      color: Theme.of(context).colorScheme.background,
      child: Consumer<MyTelemetry>(
        builder: (context, myTelemetry, child) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          // const SizedBox(height: 100, child: VerticalDivider(thickness: 2, color: Colors.black)),

          // --- Speedometer
          Container(
            constraints: const BoxConstraints(minWidth: topInstrumentsHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                myTelemetry.geo != null
                    ? Text.rich(richValue(UnitType.speed, myTelemetry.geo!.spd,
                        digits: 3,
                        autoDecimalThresh: -1,
                        valueStyle: const TextStyle(fontSize: 55),
                        unitStyle: unitStyle))
                    : const Text("--"),
              ],
            ),
          ),

          // --- Windicator
          Consumer<Wind>(
              builder: (context, wind, _) => ValueListenableBuilder<bool>(
                  valueListenable: settingsMgr.northlockWind.listenable,
                  builder: (context, northlockWind, _) {
                    return GestureDetector(
                        onTap: () {
                          showDialog(context: context, builder: (context) => WindDialog());
                        },
                        child: SizedBox(
                          width: 90,
                          height: 90,
                          child: Card(
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 4,
                                  top: 4,
                                  child: Container(
                                    width: 15,
                                    height: 15,
                                    transformAlignment: const Alignment(0, 0),
                                    transform: Matrix4.rotationZ(
                                        northlockWind ? 0 : (wind.samples.isEmpty ? 0 : -wind.samples.last.hdg)),
                                    child: northlockWind
                                        ? SvgPicture.asset(
                                            "assets/images/compass_north.svg",
                                            // fit: BoxFit.none,
                                            color: Colors.white,
                                          )
                                        : Transform.scale(
                                            scale: 1.4,
                                            child: SvgPicture.asset(
                                              "assets/images/compass.svg",
                                              // fit: BoxFit.none,
                                            ),
                                          ),
                                  ),
                                ),
                                // Wind direction indicator
                                if (wind.result != null)
                                  Align(
                                      alignment: Alignment.topCenter,
                                      child: Container(
                                        transformAlignment: const Alignment(0, 0),
                                        transform: Matrix4.rotationZ(wind.result!.windHdg +
                                            (northlockWind && myTelemetry.geo != null ? 0 : -myTelemetry.geo!.hdg)),
                                        child: SvgPicture.asset(
                                          "assets/images/wind_sock.svg",
                                          width: 80,
                                          height: 80,
                                        ),
                                      )),
                                if (wind.result != null)
                                  Align(
                                      alignment: Alignment.center,
                                      child: Text(
                                        printDouble(
                                            value: unitConverters[UnitType.speed]!(wind.result!.windSpd),
                                            digits: 2,
                                            decimals: 0),
                                        style: const TextStyle(
                                            color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                                      )),
                                if (wind.result == null)
                                  const Center(
                                      child: Text(
                                    "?",
                                    style: TextStyle(color: Colors.grey, fontSize: 20),
                                  ))
                              ],
                            ),
                          ),
                        ));
                  })),

          // --- Altimeter stack
          ValueListenableBuilder<AltimeterMode>(
              valueListenable: settingsMgr.primaryAltimeter.listenable,
              builder: (context, primaryAltimeter, _) {
                return GestureDetector(
                  onDoubleTap: () {
                    if (primaryAltimeter != AltimeterMode.msl) {
                      settingsMgr.primaryAltimeter.value = AltimeterMode.msl;
                    } else {
                      settingsMgr.primaryAltimeter.value = AltimeterMode.agl;
                    }
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    // verticalDirection:
                    //     primaryAltimeter == AltimeterMode.msl ? VerticalDirection.down : VerticalDirection.up,
                    children: [
                      Altimeter(
                        primaryAltimeter == AltimeterMode.msl
                            ? myTelemetry.geo?.alt
                            : (myTelemetry.geo?.ground != null
                                ? myTelemetry.geo!.alt - myTelemetry.geo!.ground!
                                : null),
                        valueStyle: upperStyle,
                        unitStyle: unitStyle,
                        unitTag: primaryAltimeter == AltimeterMode.msl ? "MSL" : "AGL",
                        isPrimary: true,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((myTelemetry.geo?.varioSmooth ?? 0).abs() > settingsMgr.altimeterVsiThresh.value)
                            Padding(
                              padding: const EdgeInsets.only(right: 20),
                              child: RotatedBox(
                                  quarterTurns: (myTelemetry.geo?.varioSmooth ?? 0) > 0 ? 0 : 2,
                                  child: SvgPicture.asset("assets/images/arrow.svg",
                                      height: topInstrumentsHeight / 5,
                                      color: (myTelemetry.geo?.varioSmooth ?? 0) > 0
                                          ? Colors.lightGreen
                                          : Colors.redAccent)),
                            ),
                          Altimeter(
                            primaryAltimeter != AltimeterMode.msl
                                ? myTelemetry.geo?.alt
                                : (myTelemetry.geo?.ground != null
                                    ? myTelemetry.geo!.alt - myTelemetry.geo!.ground!
                                    : null),
                            valueStyle: lowerStyle,
                            unitStyle: unitStyle,
                            unitTag: primaryAltimeter != AltimeterMode.msl ? "MSL" : "AGL",
                            isPrimary: false,
                          ),
                        ],
                      )
                    ],
                  ),
                );
              }),
        ]),
      ),
    ),
  );
}
