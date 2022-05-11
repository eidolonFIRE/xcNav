import 'dart:math';

import 'package:flutter/material.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:xcnav/dialogs/fuel_adjustment.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/screens/home.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/wind_plot.dart';

Widget moreInstrumentsDrawer() {
  return Consumer<MyTelemetry>(
    builder: (context, myTelemetry, child) => SafeArea(
      child: Dialog(
          // elevation: 10,
          backgroundColor: Colors.grey[900],
          insetPadding: const EdgeInsets.only(left: 0, right: 0, top: 60),
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Flight Timer
              ListTile(
                leading: const Icon(Icons.flight_takeoff),
                title: myTelemetry.takeOff != null
                    ? Builder(builder: (context) {
                        int remMin = ((DateTime.now().millisecondsSinceEpoch -
                                    myTelemetry
                                        .takeOff!.millisecondsSinceEpoch) /
                                60000)
                            .ceil();
                        String value = (remMin >= 60)
                            ? (remMin / 60).toStringAsFixed(1)
                            : remMin.toString();
                        String unit = (remMin >= 60) ? " hr" : " min";
                        return Text.rich(TextSpan(children: [
                          const TextSpan(
                              text: "Launched   ",
                              style: TextStyle(color: Colors.grey)),
                          TextSpan(
                              text: DateFormat("h:mm a")
                                  .format(myTelemetry.takeOff!),
                              style: Theme.of(context).textTheme.headline5),
                          const TextSpan(
                              text: " ,    ",
                              style: TextStyle(color: Colors.grey)),
                          TextSpan(
                              text: value,
                              style: Theme.of(context).textTheme.headline5),
                          TextSpan(
                              text: unit,
                              style: Theme.of(context).textTheme.headline6),
                          const TextSpan(
                              text: "  ago.",
                              style: TextStyle(color: Colors.grey)),
                        ]));
                      })
                    : const Text(
                        "On the ground...",
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
              ),
              // --- Fuel Indicator
              ListTile(
                minVerticalPadding: 0,
                leading: const Icon(Icons.local_gas_station, size: 30),
                title: GestureDetector(
                  onTap: () => {showFuelDialog(context)},
                  child: Card(
                    color: Colors.grey[800],
                    child: (myTelemetry.fuel > 0)
                        ? Builder(builder: (context) {
                            int remMin = (myTelemetry.fuel /
                                    myTelemetry.fuelBurnRate *
                                    60)
                                .ceil();
                            String value = (remMin >= 60)
                                ? (remMin / 60).toStringAsFixed(1)
                                : remMin.toString();
                            String unit = (remMin >= 60) ? "hr" : "min";
                            return Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                          text: convertFuelValue(
                                                  Provider.of<Settings>(context)
                                                      .displayUnitsFuel,
                                                  myTelemetry.fuel)
                                              .toStringAsFixed(1),
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline4),
                                      TextSpan(
                                          text: unitStrFuel[
                                              Provider.of<Settings>(context)
                                                  .displayUnitsFuel],
                                          style: instrLabel)
                                    ],
                                  ),
                                  softWrap: false,
                                ),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                          text: value,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline4),
                                      TextSpan(text: unit, style: instrLabel)
                                    ],
                                  ),
                                  softWrap: false,
                                ),
                              ],
                            );
                          })
                        : Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Text(
                              "Set Fuel Level",
                              style: Theme.of(context).textTheme.headline5,
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ),
              ),

              const Divider(thickness: 2),

              // --- Wind Chart
              Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      mainAxisSize: MainAxisSize.max,
                      // crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Wind Detector",
                          style: TextStyle(color: Colors.grey),
                        ),
                        const Divider(),
                        ListTile(
                          title: const Text("Airspeed"),
                          trailing: myTelemetry.airspeed != null
                              ? Text.rich(TextSpan(children: [
                                  TextSpan(
                                      style: const TextStyle(fontSize: 30),
                                      text: convertSpeedValue(
                                              Provider.of<Settings>(context,
                                                      listen: false)
                                                  .displayUnitsSpeed,
                                              myTelemetry.airspeed!)
                                          .toStringAsFixed(0)),
                                  TextSpan(
                                      style: const TextStyle(
                                          fontSize: 14, color: Colors.grey),
                                      text: unitStrSpeed[Provider.of<Settings>(
                                              context,
                                              listen: false)
                                          .displayUnitsSpeed]!)
                                ]))
                              : const Text("?"),
                        ),
                        ListTile(
                          title: const Text("Wind Speed"),
                          trailing: myTelemetry.lastWindCalc != null
                              ? Text.rich(TextSpan(children: [
                                  TextSpan(
                                      style: const TextStyle(
                                        fontSize: 30,
                                      ),
                                      text: convertSpeedValue(
                                              Provider.of<Settings>(context,
                                                      listen: false)
                                                  .displayUnitsSpeed,
                                              myTelemetry.windSpd)
                                          .toStringAsFixed(0)),
                                  TextSpan(
                                      style: const TextStyle(
                                          fontSize: 14, color: Colors.grey),
                                      text: unitStrSpeed[Provider.of<Settings>(
                                              context,
                                              listen: false)
                                          .displayUnitsSpeed]!)
                                ]))
                              : const Text("?"),
                        ),
                        ElevatedButton.icon(
                            label: const Text(
                              "Clear",
                              style: TextStyle(fontSize: 12),
                            ),
                            onPressed: () => {
                                  myTelemetry.windFirstSampleIndex =
                                      myTelemetry.recordGeo.length - 1
                                },
                            icon: const Icon(
                              Icons.start,
                              size: 20,
                            )),
                      ],
                    ),
                  ),

                  /// --- Wind Readings Polar Chart
                  Builder(builder: (context) {
                    if (myTelemetry.recordGeo.length < 2) return const Card();

                    // --- Circle Fit
                    // https://people.cas.uab.edu/~mosya/cl/

                    // Select our samples
                    final List<Geo> samples = myTelemetry.recordGeo.sublist(max(
                        max(0, myTelemetry.recordGeo.length - 100),
                        min(myTelemetry.recordGeo.length - 1,
                            myTelemetry.windFirstSampleIndex)));

                    // massage the samples
                    final samplesX = samples
                        .map((e) => cos(e.hdg - pi / 2) * e.spd)
                        .toList();
                    final samplesY = samples
                        .map((e) => sin(e.hdg - pi / 2) * e.spd)
                        .toList();
                    final xMean =
                        samplesX.reduce((a, b) => a + b) / samplesX.length;
                    final yMean =
                        samplesY.reduce((a, b) => a + b) / samplesY.length;
                    final maxSpd =
                        samples.reduce((a, b) => a.spd > b.spd ? a : b).spd *
                            1.1;

                    // run the algorithm
                    double mXX = 0;
                    double mYY = 0;
                    double mXY = 0;
                    double mXZ = 0;
                    double mYZ = 0;
                    double mZZ = 0;

                    for (int i = 0; i < samples.length; i++) {
                      final xI = samplesX[i] - xMean;
                      final yI = samplesY[i] - yMean;
                      final zI = xI * xI + yI * yI;
                      mXY += xI * yI;
                      mXX += xI * xI;
                      mYY += yI * yI;
                      mXZ += xI * zI;
                      mYZ += yI * zI;
                      mZZ += zI * zI;
                    }

                    mXX /= samples.length;
                    mYY /= samples.length;
                    mXY /= samples.length;
                    mXZ /= samples.length;
                    mYZ /= samples.length;
                    mZZ /= samples.length;

                    final double mZ = mXX + mYY;
                    final double covXY = mXX * mYY - mXY * mXY;
                    final double a3 = 4 * mZ;
                    final double a2 = -3 * mZ * mZ - mZZ;
                    final double a1 = mZZ * mZ +
                        4 * covXY * mZ -
                        mXZ * mXZ -
                        mYZ * mYZ -
                        mZ * mZ * mZ;
                    final double a0 = mXZ * mXZ * mYY +
                        mYZ * mYZ * mXX -
                        mZZ * covXY -
                        2 * mXZ * mYZ * mXY +
                        mZ * mZ * covXY;
                    final double a22 = a2 + a2;
                    final double a33 = a3 + a3 + a3;

                    double xnew = 0;
                    double ynew = 1e+20;
                    const epsilon = 1e-6;
                    const iterMax = 20;

                    for (int iter = 1; iter < iterMax; iter++) {
                      double yold = ynew;
                      ynew = a0 + xnew * (a1 + xnew * (a2 + xnew * a3));
                      if ((ynew).abs() > (yold).abs()) {
                        debugPrint(
                            "Newton-Taubin goes wrong direction: |ynew| > |yold|");
                        xnew = 0;
                        break;
                      }
                      double dY = a1 + xnew * (a22 + xnew * a33);
                      double xold = xnew;
                      xnew = xold - ynew / dY;
                      if (((xnew - xold) / xnew).abs() < epsilon) break;
                      if (iter >= iterMax) {
                        debugPrint("Newton-Taubin will not converge");
                        xnew = 0;
                      }
                      if (xnew < 0) {
                        debugPrint("Newton-Taubin negative root:  x=$xnew");
                        xnew = 0;
                      }
                    }

                    // compute final offset and radius
                    final det = xnew * xnew - xnew * mZ + covXY;
                    final xCenter = (mXZ * (mYY - xnew) - mYZ * mXY) / det / 2;
                    final yCenter = (mYZ * (mXX - xnew) - mXZ * mXY) / det / 2;
                    final radius = sqrt(pow(xCenter, 2) + pow(yCenter, 2) + mZ);
                    myTelemetry.windSpd =
                        sqrt(pow(xCenter + xMean, 2) + pow(yCenter + yMean, 2));
                    myTelemetry.windHdg = atan2(yCenter, xCenter) % (2 * pi);
                    myTelemetry.airspeed = radius;
                    myTelemetry.lastWindCalc = DateTime.now();

                    return Card(
                      color: Colors.black26,
                      child: Container(
                        // width: MediaQuery.of(context).size.width * 2 / 3,
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 2 / 3,
                            maxHeight: 200),

                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRect(
                                child: CustomPaint(
                                  painter: WindPlotPainter(
                                      Colors.blue,
                                      3,
                                      samplesX,
                                      samplesY,
                                      maxSpd,
                                      Offset(xCenter + xMean, yCenter + yMean),
                                      radius),
                                ),
                              ),
                              const Align(
                                  alignment: Alignment.topCenter,
                                  child: Text("N")),
                              const Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Text("S")),
                              const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text("W")),
                              const Align(
                                  alignment: Alignment.centerRight,
                                  child: Text("E")),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),

              const Divider(thickness: 2),

              // --- Altitude Chart
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: charts.TimeSeriesChart(
                  [
                    charts.Series<Geo, DateTime>(
                      id: "Altitude",
                      data: myTelemetry.recordGeo,
                      colorFn: (_, __) =>
                          charts.MaterialPalette.blue.shadeDefault,
                      domainFn: (value, _) =>
                          DateTime.fromMillisecondsSinceEpoch(value.time),
                      measureFn: (value, _) => convertDistValueFine(
                          Provider.of<Settings>(context, listen: false)
                              .displayUnitsDist,
                          value.alt),
                    )
                  ],
                  defaultRenderer: charts.LineRendererConfig(
                      includeArea: true, stacked: true),
                  animate: false,

                  behaviors: [
                    charts.ChartTitle(
                        "Altitude   (${unitStrDistFine[Provider.of<Settings>(context).displayUnitsDist]} )",
                        behaviorPosition: charts.BehaviorPosition.start,
                        titleOutsideJustification:
                            charts.OutsideJustification.middleDrawArea,
                        titleStyleSpec: const charts.TextStyleSpec(
                            color: charts.MaterialPalette.white)),
                  ],

                  domainAxis: const charts.DateTimeAxisSpec(
                      renderSpec: charts.SmallTickRendererSpec(

                          // Tick and Label styling here.
                          labelStyle: charts.TextStyleSpec(
                              fontSize: 14, // size in Pts.
                              color: charts.MaterialPalette.white),

                          // Change the line colors to match text color.
                          lineStyle: charts.LineStyleSpec(
                              color: charts.MaterialPalette.white))),

                  /// Assign a custom style for the measure axis.
                  primaryMeasureAxis: const charts.NumericAxisSpec(
                      tickProviderSpec: charts.BasicNumericTickProviderSpec(
                          desiredMinTickCount: 4),
                      renderSpec: charts.GridlineRendererSpec(

                          // Tick and Label styling here.
                          labelStyle: charts.TextStyleSpec(
                              fontSize: 14, // size in Pts.
                              color: charts.MaterialPalette.white),

                          // Change the line colors to match text color.
                          lineStyle: charts.LineStyleSpec(
                              color: charts.MaterialPalette.white))),
                ),
              ),
            ],
          )),
    ),
  );
}
