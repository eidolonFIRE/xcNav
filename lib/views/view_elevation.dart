import 'dart:math';

import 'package:flutter/material.dart';

import 'package:charts_flutter/flutter.dart' as charts;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/units.dart';

class ViewElevation extends StatefulWidget {
  const ViewElevation({Key? key}) : super(key: key);

  @override
  State<ViewElevation> createState() => ViewElevationState();
}

class ViewElevationState extends State<ViewElevation> {
  @override
  Widget build(BuildContext context) {
    return Consumer<MyTelemetry>(builder: (context, myTelemetry, _) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // --- Flight Timer
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: myTelemetry.takeOff != null
                ? Builder(builder: (context) {
                    int remMin =
                        ((DateTime.now().millisecondsSinceEpoch - myTelemetry.takeOff!.millisecondsSinceEpoch) / 60000)
                            .ceil();
                    String value = (remMin >= 60) ? (remMin / 60).toStringAsFixed(1) : remMin.toString();
                    String unit = (remMin >= 60) ? " hr" : " min";
                    return Text.rich(TextSpan(children: [
                      const TextSpan(text: "Launched   ", style: TextStyle(color: Colors.grey)),
                      TextSpan(
                          text: DateFormat("h:mm a").format(myTelemetry.takeOff!),
                          style: Theme.of(context).textTheme.headline5),
                      const TextSpan(text: " ,    ", style: TextStyle(color: Colors.grey)),
                      TextSpan(text: value, style: Theme.of(context).textTheme.headline5),
                      TextSpan(text: unit, style: Theme.of(context).textTheme.headline6),
                      const TextSpan(text: "  ago.", style: TextStyle(color: Colors.grey)),
                    ]));
                  })
                : const Text(
                    "On the ground...",
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: charts.TimeSeriesChart(
              [
                charts.Series<Geo, DateTime>(
                  id: "Ground",
                  data: myTelemetry.recordGeo.sublist(max(0, myTelemetry.recordGeo.length - 200)),
                  colorFn: (_, __) => charts.MaterialPalette.deepOrange.shadeDefault,
                  areaColorFn: (_, __) => const charts.Color(r: 125, g: 85, b: 72, a: 200),
                  domainFn: (value, _) => DateTime.fromMillisecondsSinceEpoch(value.time),
                  measureFn: (value, _) => unitConverters[UnitType.distFine]!(value.ground ?? 0),
                ),
                charts.Series<Geo, DateTime>(
                  id: "Altitude",
                  data: myTelemetry.recordGeo.sublist(max(0, myTelemetry.recordGeo.length - 200)),
                  colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
                  domainFn: (value, _) => DateTime.fromMillisecondsSinceEpoch(value.time),
                  measureFn: (value, _) => unitConverters[UnitType.distFine]!(value.alt - (value.ground ?? 0)),
                ),
              ],
              defaultRenderer: charts.LineRendererConfig(includeArea: true, stacked: true),
              animate: false,

              behaviors: [
                charts.ChartTitle("Altitude   (${getUnitStr(UnitType.distFine)})",
                    behaviorPosition: charts.BehaviorPosition.top,
                    titleOutsideJustification: charts.OutsideJustification.middleDrawArea,
                    titleStyleSpec: const charts.TextStyleSpec(color: charts.MaterialPalette.white)),
              ],

              domainAxis: const charts.DateTimeAxisSpec(
                  renderSpec: charts.SmallTickRendererSpec(

                      // Tick and Label styling here.
                      labelStyle: charts.TextStyleSpec(
                          fontSize: 14, // size in Pts.
                          color: charts.MaterialPalette.white),

                      // Change the line colors to match text color.
                      lineStyle: charts.LineStyleSpec(color: charts.MaterialPalette.white))),

              /// Assign a custom style for the measure axis.
              primaryMeasureAxis: const charts.NumericAxisSpec(
                  tickProviderSpec: charts.BasicNumericTickProviderSpec(desiredMinTickCount: 6),
                  renderSpec: charts.GridlineRendererSpec(

                      // Tick and Label styling here.
                      labelStyle: charts.TextStyleSpec(
                          fontSize: 14, // size in Pts.
                          color: charts.MaterialPalette.white),

                      // Change the line colors to match text color.
                      lineStyle: charts.LineStyleSpec(color: charts.MaterialPalette.white))),
            ),
          ),
        ],
      );
    });
  }
}
