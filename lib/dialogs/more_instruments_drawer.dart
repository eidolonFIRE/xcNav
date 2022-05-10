import 'package:flutter/material.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:scidart/numdart.dart';
// import 'package:scidart/scidart.dart';

import 'package:xcnav/dialogs/fuel_adjustment.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/screens/home.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/polar_plot.dart';

/// o = offset
/// s = sin magnitude
/// c = cosine magnitude
Array sinusoid(double o, double s, double c, Array x) {
  return Array(x.map((e) => sin(e) * s + o).toList()) +
      Array(x.map((e) => cos(e) * c).toList());
}

Array2d jacobian(Function f, double o, double s, double c, Array x) {
  const double eps = 1e-4;
  final Array gradO =
      arrayDivisionToScalar(f(o + eps, s, c, x) - f(o - eps, s, c, x), 2 * eps);
  final Array gradS =
      arrayDivisionToScalar(f(o, s + eps, c, x) - f(o, s - eps, c, x), 2 * eps);
  final Array gradC =
      arrayDivisionToScalar(f(o, s, c + eps, x) - f(o, s, c - eps, x), 2 * eps);
  return matrixTranspose(Array2d([gradO, gradS, gradC]));
}

Array gaussNewton(Function f, Array hdg, Array spd, double o, double s,
    double c, double tol, double maxIter) {
  var next = Array([o, s, c]);
  var prev = next;
  for (int iter = 0; iter < maxIter; iter++) {
    prev = next;
    final j = jacobian(f, prev[0], prev[1], prev[2], hdg);
    final jT = matrixTranspose(j);
    final dy = spd - f(prev[0], prev[1], prev[2], hdg);
    final foo = matrixDot(matrixDot(matrixInverse(matrixDot(jT, j)), jT),
        matrixTranspose(Array2d([dy])));
    next = prev + matrixTranspose(foo)[0];

    // Constrains
    // next[0] = max(0, next[0]);
    // next[1] = min(15, max(-15, next[1]));
    // next[2] = min(15, max(-15, next[2]));
    debugPrint(next.toString());

    if (matrixNormOne(Array2d([prev - next])) < tol) {
      break;
    }
  }
  return next;
}

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
                      children: [
                        const Text("Wind Indicator"),
                        const Text("( WIP )"),
                        ElevatedButton.icon(
                            label: const Text(
                              "Restart",
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
                  Builder(builder: (context) {
                    if (myTelemetry.recordGeo.length < 5) return Container();

                    final start = DateTime.now().millisecondsSinceEpoch;

                    final List<Geo> samples = myTelemetry.recordGeo.sublist(max(
                        max(0, myTelemetry.recordGeo.length - 100),
                        min(myTelemetry.recordGeo.length - 1,
                            myTelemetry.windFirstSampleIndex)));

                    final samplesMatrix = Array2d(
                        samples.map((e) => Array([e.hdg, e.spd])).toList());

                    final double minSpd =
                        samples.reduce((a, b) => a.spd < b.spd ? a : b).spd;
                    final double maxSpd =
                        samples.reduce((a, b) => a.spd > b.spd ? a : b).spd;

                    Array windFit = gaussNewton(
                        sinusoid,
                        Array(samples.map((e) => e.hdg).toList()),
                        Array(samples.map((e) => e.spd).toList()),
                        (minSpd + maxSpd) / 2,
                        0,
                        0,
                        1e-4,
                        10);

                    Array2d windSin = Array2d([Array([]), Array([])]);
                    for (int i = 0; i < 48; i++) {
                      windSin[0].add(2 * pi * i / 47 - pi);
                    }
                    final Array y = sinusoid(
                        windFit[0], windFit[1], windFit[2], windSin[0]);

                    windSin[1] = y;
                    windSin = matrixTranspose(windSin);

                    final end = DateTime.now().millisecondsSinceEpoch;
                    debugPrint("---- Wind Computed: ${end - start}ms");

                    return Container(
                      // width: MediaQuery.of(context).size.width * 2 / 3,
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 2 / 3,
                          maxHeight: 200),
                      // clipBehavior: Clip.hardEdge,

                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              painter: PolarPlotPainter(
                                  Colors.amber, 2, windSin, maxSpd, true),
                            ),
                            CustomPaint(
                              painter: PolarPlotPainter(
                                  Colors.blue, 3, samplesMatrix, maxSpd, false),
                            )
                          ],
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
