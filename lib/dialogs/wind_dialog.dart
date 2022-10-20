import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/wind_plot.dart';

void showWindDialog(BuildContext context) {
  const valueStyle = TextStyle(fontSize: 35, color: Colors.white);
  const unitStyle = TextStyle(fontSize: 16, color: Colors.grey, fontStyle: FontStyle.italic);

  showDialog(
    context: context,
    builder: (context) => Consumer<Wind>(
      builder: (context, wind, child) => Dialog(
        insetPadding: const EdgeInsets.only(top: 100, left: 10, right: 10),
        alignment: Alignment.topCenter,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        "Wind Detector",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Icon(
                          Icons.flight,
                          size: 35,
                        ),
                        Text.rich(wind.result != null
                            ? richValue(UnitType.speed, wind.result!.airspeed,
                                digits: 3, valueStyle: valueStyle, unitStyle: unitStyle)
                            : const TextSpan(text: "?", style: valueStyle)),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Icon(
                          Icons.air,
                          size: 35,
                        ),
                        Text.rich(
                          wind.result != null
                              ? richValue(UnitType.speed, wind.result!.windSpd,
                                  digits: 3, valueStyle: valueStyle, unitStyle: unitStyle)
                              : const TextSpan(text: "?", style: valueStyle),
                        ),
                      ]),
                    )
                  ],
                ),
              ),

              /// --- Wind Readings Polar Chart
              Card(
                color: Colors.black26,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width - 180,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        wind.result == null
                            ? Center(
                                child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Padding(
                                    padding: EdgeInsets.all(10.0),
                                    child: Text("Slowly Turn 1/4 Circle", style: TextStyle(fontSize: 18)),
                                  ),
                                  CircularProgressIndicator(
                                    strokeWidth: 3,
                                  )
                                ],
                              ))
                            : ClipRect(
                                child: CustomPaint(
                                  painter: WindPlotPainter(3, wind.result!.samplesX, wind.result!.samplesY,
                                      wind.result!.maxSpd * 1.1, wind.result!.circleCenter, wind.result!.airspeed),
                                ),
                              ),
                        const Align(alignment: Alignment.topCenter, child: Text("N")),
                        const Align(alignment: Alignment.bottomCenter, child: Text("S")),
                        const Align(alignment: Alignment.centerLeft, child: Text("W")),
                        const Align(alignment: Alignment.centerRight, child: Text("E")),
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    ),
  );
}
