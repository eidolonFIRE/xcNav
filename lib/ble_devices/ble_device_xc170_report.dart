import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/trendlines.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

class Xc170ReportScreen extends StatefulWidget {
  const Xc170ReportScreen({super.key});

  @override
  State<Xc170ReportScreen> createState() => _Xc170ReportScreenState();
}

class _Xc170ReportScreenState extends State<Xc170ReportScreen> {
  bool logLoaded = false;
  late FlightLog log;
  String? logKey;

  @override
  void didChangeDependencies() {
    if (!logLoaded) {
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, String>;
      logKey ??= args["logKey"];
      debugPrint("Loading log $logKey");

      log = logStore.logs[logKey]!;
    }
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final fuelData = log.getBleDeviceSeries("xc170", "fuel");
    final fuelTrend = getLinearTrendlineTuned(values: fuelData, outlierThresh: 0.5, iterations: 1);

    final chtData = log.getBleDeviceSeries("xc170", "cht");
    final egtData = log.getBleDeviceSeries("xc170", "egt");
    final rpmData = log.getBleDeviceSeries("xc170", "rpm");
    final fanAmpsData = log.getBleDeviceSeries("xc170", "fanAmps"); // milliamps
    double fanAmpsIntegral = 0;
    for (int i = 0; i < fanAmpsData.length - 1; i++) {
      final mean = fanAmpsData[i].value + fanAmpsData[i + 1].value;
      fanAmpsIntegral += mean * (fanAmpsData[i + 1].time - fanAmpsData[i].time) / 1000 / 3600;
    }

    final rpmVario = log.varioLogSmoothed
        .map((each) => TimestampValue<double>(
            rpmData[nearestIndex(rpmData.map((e) => e.time.toDouble()).toList(), each.time.toDouble())].value.round(),
            unitConverters[UnitType.vario]!(each.value)))
        .sorted((a, b) => a.time - b.time)
        .toList();
    final rpmVarioTrend = getLinearTrendlineTuned(values: rpmVario, outlierThresh: 100, iterations: 2);

    return Scaffold(
        appBar: AppBar(
          title: Text("Xc170 Report"),
        ),
        body: Column(children: [
          /// --- Cooling power used
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: "Cooling fan used: "),
              TextSpan(text: fanAmpsIntegral.toStringAsFixed(1)),
              TextSpan(text: " Ahr,  "),
              TextSpan(
                  text: (fanAmpsIntegral / (fanAmpsData.last.time - fanAmpsData.first.time) * 1000 * 3600)
                      .toStringAsFixed(2)),
              TextSpan(text: " Amps avg")
            ])),
          ),

          Divider(
            height: 8,
          ),

          /// --- Fuel Chart
          Text("Fuel / Time"),
          Expanded(
              child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Stack(
              children: [
                LineChart(LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                          dotData: const FlDotData(show: false),
                          spots: fuelData
                              .map((e) => FlSpot(e.time.toDouble(), unitConverters[UnitType.fuel]!(e.value)))
                              .toList(),
                          barWidth: 0,
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                                colors: [Colors.lightGreen, Colors.cyan.withAlpha(50)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter),
                          )),
                      if (fuelData.length > 2)
                        LineChartBarData(
                            spots: fuelTrend.points.map((e) => FlSpot(e.time.toDouble(), e.value)).toList(),
                            barWidth: 2,
                            dashArray: [10, 4],
                            color: Colors.white)
                    ],
                    titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                            sideTitleAlignment: SideTitleAlignment.inside,
                            drawBelowEverything: false,
                            sideTitles:
                                SideTitles(showTitles: true, minIncluded: false, reservedSize: 40, maxIncluded: false)),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false, maxIncluded: false, minIncluded: false))))),

                /// --- Stats
                Align(
                    alignment: Alignment.topRight,
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: Colors.grey.shade800.withAlpha(100),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(TextSpan(children: [
                              WidgetSpan(
                                  child: Icon(
                                Icons.trending_down,
                                size: 16,
                              )),
                              TextSpan(text: "  "),
                              TextSpan(text: (-fuelTrend.slope * 1000 * 60 * 60).toStringAsFixed(1)),
                              TextSpan(text: fuelRateStr),
                            ])),
                            Text.rich(TextSpan(children: [
                              WidgetSpan(
                                  child: Icon(
                                Icons.error_outline,
                                size: 16,
                              )),
                              TextSpan(text: "  "),
                              TextSpan(text: (fuelTrend.errorTotal / fuelData.length * 100).round().toString()),
                              TextSpan(text: "%"),
                            ])),
                          ],
                        ),
                      ),
                    ))
              ],
            ),
          )),

          /// --- Temp/RPM chart
          Text("Temperature / RPM"),
          Expanded(
              child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Stack(
              children: [
                ScatterChart(ScatterChartData(
                    maxY: 250,
                    minY: 190,
                    clipData: FlClipData.all(),
                    scatterSpots: chtData
                            .map((eachCht) => ScatterSpot(
                                rpmData[nearestIndex(rpmData.map((e) => e.time.toDouble()).toList(), eachCht.time.toDouble())].value, eachCht.value,
                                dotPainter: FlDotCirclePainter(
                                    radius: 3,
                                    strokeWidth: 0,
                                    color: Colors.amber
                                        .withAlpha(min(255, max(1.0, 30000.0 / chtData.length.toDouble()).round())))))
                            .toList() +
                        egtData
                            .map((eachEgt) => ScatterSpot(rpmData[nearestIndex(rpmData.map((e) => e.time.toDouble()).toList(), eachEgt.time.toDouble())].value,
                                (eachEgt.value - 400) * 60 / 300 + 190,
                                dotPainter: FlDotCirclePainter(
                                    radius: 3,
                                    strokeWidth: 0,
                                    color: Colors.cyanAccent.withAlpha(min(255, max(1.0, 30000.0 / egtData.length.toDouble()).round())))))
                            .toList(),
                    titlesData: FlTitlesData(
                        rightTitles: AxisTitles(
                            drawBelowEverything: false,
                            sideTitleAlignment: SideTitleAlignment.inside,
                            sideTitles: SideTitles(
                              maxIncluded: false,
                              minIncluded: false,
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) =>
                                  Text(((value - 190) * 300 / 60 + 400).round().toString()),
                            )),
                        leftTitles: AxisTitles(drawBelowEverything: false, sideTitleAlignment: SideTitleAlignment.inside, sideTitles: SideTitles(showTitles: true, reservedSize: 40, minIncluded: false, maxIncluded: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, minIncluded: false, maxIncluded: false)),
                        topTitles: AxisTitles(sideTitleAlignment: SideTitleAlignment.inside, sideTitles: SideTitles(showTitles: false))))),

                /// --- Labels
                Align(
                    alignment: Alignment.topLeft,
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: Colors.grey.shade800.withAlpha(100),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Text.rich(TextSpan(children: [
                          WidgetSpan(
                              child: Icon(
                            Icons.circle,
                            size: 16,
                            color: Colors.amber,
                          )),
                          TextSpan(text: "CHT"),
                        ])),
                      ),
                    )),
                Align(
                    alignment: Alignment.topRight,
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: Colors.grey.shade800.withAlpha(100),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Text.rich(TextSpan(children: [
                          WidgetSpan(
                              child: Icon(
                            Icons.circle,
                            size: 16,
                            color: Colors.cyan,
                          )),
                          TextSpan(text: "EGT"),
                        ])),
                      ),
                    ))
              ],
            ),
          )),

          /// --- Vario/RPM chart
          Text("Vario / RPM"),
          Expanded(
              child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Stack(
              children: [
                LineChart(LineChartData(
                    clipData: FlClipData.all(),
                    lineTouchData: LineTouchData(enabled: false),
                    lineBarsData: [
                      LineChartBarData(
                          spots: rpmVario
                              .map((each) => ScatterSpot(
                                    each.time.toDouble(),
                                    each.value,
                                  ))
                              .toList(),
                          barWidth: 0,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, value, data, i) {
                              return FlDotCirclePainter(
                                  radius: 3,
                                  strokeWidth: 0,
                                  color: Colors.lightGreenAccent.withAlpha(
                                      min(255, max(1.0, 30000.0 / log.varioLogSmoothed.length.toDouble()).round())));
                            },
                          )),
                      // --- Trendline
                      LineChartBarData(
                          spots: rpmVarioTrend.points
                              .map((each) => ScatterSpot(
                                    each.time.toDouble(),
                                    each.value,
                                  ))
                              .toList(),
                          barWidth: 2,
                          dashArray: [10, 4],
                          color: Colors.white)
                    ],
                    titlesData: FlTitlesData(
                        rightTitles: AxisTitles(
                            sideTitles: SideTitles(
                          showTitles: false,
                        )),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true, minIncluded: false, maxIncluded: false)),
                        leftTitles: AxisTitles(
                            drawBelowEverything: false,
                            sideTitleAlignment: SideTitleAlignment.inside,
                            sideTitles:
                                SideTitles(showTitles: true, minIncluded: false, maxIncluded: false, reservedSize: 40)),
                        topTitles: AxisTitles(
                            sideTitleAlignment: SideTitleAlignment.inside,
                            sideTitles: SideTitles(showTitles: false))))),

                /// --- Stats
                Align(
                    alignment: Alignment.topRight,
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: Colors.grey.shade800.withAlpha(100),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(TextSpan(children: [
                              WidgetSpan(
                                  child: Icon(
                                Icons.unfold_less,
                                size: 16,
                              )),
                              TextSpan(text: (-rpmVarioTrend.offset / rpmVarioTrend.slope).round().toString()),
                            ])),
                          ],
                        ),
                      ),
                    ))
              ],
            ),
          )),
        ]));
  }
}
