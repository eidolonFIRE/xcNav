import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/dialogs/wind_dialog.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';

Widget topInstruments(BuildContext context) {
  const upperStyle = TextStyle(fontSize: 45);
  const lowerStyle = TextStyle(fontSize: 16);
  final TextStyle unitStyle = TextStyle(fontSize: 14, color: Colors.grey.shade400, fontStyle: FontStyle.italic);

  return Padding(
    padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
    child: Container(
      color: Theme.of(context).backgroundColor,
      child: Consumer2<MyTelemetry, Settings>(
        builder: (context, myTelemetry, settings, child) =>
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          // const SizedBox(height: 100, child: VerticalDivider(thickness: 2, color: Colors.black)),

          // --- Speedometer
          Container(
            constraints: const BoxConstraints(minWidth: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(richValue(UnitType.speed, myTelemetry.geo.spd,
                    digits: 3, autoDecimalThresh: -1, valueStyle: const TextStyle(fontSize: 55), unitStyle: unitStyle)),
              ],
            ),
          ),

          // --- Windicator
          Consumer<Wind>(
              builder: (context, wind, _) => GestureDetector(
                  onTap: () {
                    showWindDialog(context);
                  },
                  child: SizedBox(
                    width: 90,
                    height: 90,
                    child: Card(
                      child: wind.result != null
                          ? Stack(
                              children: [
                                // Wind direction indicator
                                Align(
                                    alignment: Alignment.topCenter,
                                    child: Container(
                                      transformAlignment: const Alignment(0, 0),
                                      transform: Matrix4.rotationZ(
                                          wind.result!.windHdg + (settings.northlockWind ? 0 : -myTelemetry.geo.hdg)),
                                      child: SvgPicture.asset(
                                        "assets/images/arrow.svg",
                                        width: 80,
                                        height: 80,
                                        // color: Colors.blue,
                                      ),
                                    )),
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
                              ],
                            )
                          : const Center(
                              child: Text(
                              "?",
                              style: lowerStyle,
                            )),
                    ),
                  ))),

          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Consumer<Settings>(builder: (context, settings, _) {
              return GestureDetector(
                onDoubleTap: () {
                  if (settings.altInstr != "MSL") {
                    settings.altInstr = "MSL";
                  } else {
                    settings.altInstr = "AGL";
                  }
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  verticalDirection: settings.altInstr == "MSL" ? VerticalDirection.down : VerticalDirection.up,
                  children: [
                    Altimeter(
                      myTelemetry.geo.alt,
                      valueStyle: settings.altInstr == "MSL" ? upperStyle : lowerStyle,
                      unitStyle: unitStyle,
                      unitTag: "MSL",
                      isPrimary: settings.altInstr == "MSL",
                    ),
                    Altimeter(
                      myTelemetry.geo.ground != null ? myTelemetry.geo.alt - myTelemetry.geo.ground! : null,
                      valueStyle: settings.altInstr == "AGL" ? upperStyle : lowerStyle,
                      unitStyle: unitStyle,
                      unitTag: "AGL",
                      isPrimary: settings.altInstr == "AGL",
                    )
                  ],
                ),
              );
            }),
          ),

          //         DropdownMenuItem(
          //           value: "Den",
          //           alignment: Alignment.centerRight,
          //           child: FutureBuilder<double?>(
          //             future: sampleDem(myTelemetry.geo.latLng, offset: -myTelemetry.geo.alt),
          //             builder: ((context, snapshot) => snapshot.hasData && snapshot.data != null
          //                 ? Altimeter(
          //                     1000,
          //                     valueStyle: instrUpper,
          //                     unitStyle: instrLabel,
          //                     unitTag: "Den",
          //                   )
          //                 : const CircularProgressIndicator()),
          //           ),
          //         )
        ]),
      ),
    ),
  );
}
