import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';
import 'package:xcnav/widgets/windicator.dart';

const topInstrumentsHeight = 90.0;

class TopInstruments extends StatelessWidget {
  final MyTelemetry myTelemetry;

  const TopInstruments({super.key, required this.myTelemetry});

  @override
  Widget build(BuildContext context) {
    const upperStyle = TextStyle(fontSize: 45);
    const lowerStyle = TextStyle(fontSize: 16);
    final TextStyle unitStyle = TextStyle(fontSize: 14, color: Colors.grey.shade400);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: ListenableBuilder(
          listenable: myTelemetry,
          builder: (context, child) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            // const SizedBox(height: 100, child: VerticalDivider(thickness: 2, color: Colors.black)),

            // --- Speedometer (tap for big instruments)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pushNamed(context, "/bigInstruments"),
              child: Stack(
                children: [
                  Container(
                    constraints: const BoxConstraints(minWidth: topInstrumentsHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        myTelemetry.geo != null
                            ? Text.rich(richValue(UnitType.speed, myTelemetry.speedSmooth.value,
                                digits: 3,
                                autoDecimalThresh: -1,
                                valueStyle: const TextStyle(fontSize: 55),
                                unitStyle: unitStyle))
                            : const Text("--"),
                      ],
                    ),
                  ),
                  const Positioned(left: 0, top: 0, child: Icon(Icons.open_in_full, size: 14, color: Colors.white54)),
                ],
              ),
            ),

            // --- Windicator
            Windicator(myTelemetry: myTelemetry),

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
                            if ((myTelemetry.varioSmooth.value).abs() > settingsMgr.altimeterVsiThresh.value)
                              Padding(
                                  padding: const EdgeInsets.only(right: 20),
                                  child: RotatedBox(
                                      quarterTurns: (myTelemetry.varioSmooth.value) > 0 ? 0 : 2,
                                      child: SvgPicture.asset("assets/images/arrow.svg",
                                          height: topInstrumentsHeight / 5,
                                          colorFilter: ColorFilter.mode(
                                              (myTelemetry.varioSmooth.value) > 0
                                                  ? Colors.lightGreen
                                                  : Colors.redAccent,
                                              BlendMode.srcIn)))),
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
}
