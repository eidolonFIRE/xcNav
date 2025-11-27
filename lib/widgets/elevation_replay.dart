import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/log_view.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

class ElevationReplay extends StatelessWidget {
  final LogView logView;
  final void Function(int index)? onSelectedGForce;
  final void Function(double? time)? onSelectedTime;

  final bool showVario;
  final TransformationController transformController;

  const ElevationReplay({
    super.key,
    required this.showVario,
    required this.logView,
    this.onSelectedGForce,
    this.onSelectedTime,
    required this.transformController,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: logView,
        builder: (context, _) {
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    LineChart(
                        transformationConfig: FlTransformationConfig(
                            scaleAxis: FlScaleAxis.horizontal,
                            transformationController: transformController,
                            maxScale: 300),
                        LineChartData(
                            gridData: FlGridData(verticalInterval: verticalLineInterval(logView.timeRange.duration)),
                            clipData: FlClipData.horizontal(),
                            maxY: logView.samples.map((e) => unitConverters[UnitType.distFine]!(e.alt)).max + 100,
                            minY: unitConverters[UnitType.distFine]!(min(logView.log.samples.map((e) => e.alt).min - 10,
                                logView.log.samples.map((e) => e.ground).nonNulls.min - 10)),
                            lineTouchData: LineTouchData(
                                getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                              return spotIndexes.map((spotIndex) {
                                if (barData.spots[0].y ==
                                    unitConverters[UnitType.distFine]!(logView.log.samples.first.alt)) {
                                  return TouchedSpotIndicatorData(const FlLine(color: Colors.white, strokeWidth: 2),
                                      FlDotData(getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                        radius: 3, color: Colors.white, strokeWidth: 2, strokeColor: Colors.white);
                                  }));
                                } else {
                                  return null;
                                }
                              }).toList();
                            }, touchTooltipData:
                                    LineTouchTooltipData(getTooltipItems: (List<LineBarSpot> touchedSpots) {
                              WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
                                onSelectedTime?.call(touchedSpots[0].x);
                              });
                              return [
                                LineTooltipItem(
                                  "${touchedSpots[0].y.round()} ${getUnitStr(UnitType.distFine)} MSL",
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                                if (touchedSpots.length > 1)
                                  LineTooltipItem(
                                    "${(touchedSpots[0].y - touchedSpots[1].y).round()} ${getUnitStr(UnitType.distFine)} AGL",
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  )
                              ];
                            })),
                            lineBarsData: [
                              LineChartBarData(
                                  barWidth: 0,
                                  dotData: const FlDotData(show: false),
                                  spots: logView.log.samples
                                      .where((e) => e.ground != null)
                                      .map((e) =>
                                          FlSpot(e.time.toDouble(), unitConverters[UnitType.distFine]!(e.ground!)))
                                      .toList(),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: const Color.fromARGB(255, 133, 81, 39),
                                  )),
                              LineChartBarData(
                                  spots: logView.log.samples
                                      .map((e) => FlSpot(e.time.toDouble(), unitConverters[UnitType.distFine]!(e.alt)))
                                      .toList(),
                                  barWidth: 2,
                                  dotData: const FlDotData(show: false),
                                  color: Colors.cyanAccent),
                            ],
                            titlesData: const FlTitlesData(
                                leftTitles: AxisTitles(
                                    sideTitleAlignment: SideTitleAlignment.inside,
                                    drawBelowEverything: false,
                                    sideTitles: SideTitles(
                                        showTitles: true, minIncluded: false, reservedSize: 40, maxIncluded: false)),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))))),

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
                                    Icons.timer,
                                    size: 16,
                                  )),
                                  TextSpan(text: "  "),
                                  TextSpan(
                                      text: simpleHrMinSec(Duration(
                                          milliseconds: logView.samples.map((e) => e.time).toList().max -
                                              logView.samples.map((e) => e.time).toList().min)))
                                ])),
                                Text.rich(TextSpan(children: [
                                  WidgetSpan(
                                      child: Icon(
                                    Icons.vertical_align_top,
                                    size: 18,
                                  )),
                                  TextSpan(
                                      text:
                                          "  ${logView.samples.map((e) => unitConverters[UnitType.distFine]!(e.alt)).max.round()} "),
                                  TextSpan(text: getUnitStr(UnitType.distFine))
                                ])),
                                Text.rich(TextSpan(children: [
                                  WidgetSpan(
                                      child: Icon(
                                    Icons.show_chart,
                                    size: 18,
                                  )),
                                  TextSpan(
                                      text:
                                          "  ${unitConverters[UnitType.distFine]!(calcAltGained(logView.samples)).round()} "),
                                  TextSpan(text: getUnitStr(UnitType.distFine))
                                ])),
                              ],
                            ),
                          ),
                        ))
                  ],
                ),
              ),
              Container(
                height: 10,
              ),
              if (showVario)
                Expanded(
                    child: Stack(
                  children: [
                    LineChart(
                        transformationConfig: FlTransformationConfig(
                            scaleAxis: FlScaleAxis.horizontal,
                            transformationController: transformController,
                            maxScale: 300),
                        LineChartData(
                            clipData: FlClipData.horizontal(),
                            gridData: FlGridData(verticalInterval: verticalLineInterval(logView.timeRange.duration)),
                            lineBarsData: [
                              LineChartBarData(
                                aboveBarData:
                                    BarAreaData(show: true, color: Colors.amber, applyCutOffY: true, cutOffY: 0),
                                belowBarData:
                                    BarAreaData(show: true, color: Colors.green, applyCutOffY: true, cutOffY: 0),
                                dotData: FlDotData(show: false),
                                barWidth: 1,
                                color: Colors.white,
                                spots: logView.log.varioLogSmoothed
                                    .map((e) => FlSpot(e.time.toDouble(), unitConverters[UnitType.vario]!(e.value)))
                                    .toList(),
                              )
                            ],
                            lineTouchData: LineTouchData(
                                getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                              return spotIndexes.map((spotIndex) {
                                return TouchedSpotIndicatorData(const FlLine(color: Colors.white, strokeWidth: 2),
                                    FlDotData(getDotPainter: (spot, percent, barData, index) {
                                  return FlDotCirclePainter(
                                      radius: 3, color: Colors.white, strokeWidth: 2, strokeColor: Colors.white);
                                }));
                              }).toList();
                            }, touchTooltipData:
                                    LineTouchTooltipData(getTooltipItems: (List<LineBarSpot> touchedSpots) {
                              WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
                                onSelectedTime?.call(touchedSpots[0].x);
                              });
                              return touchedSpots.map((LineBarSpot touchedSpot) {
                                return LineTooltipItem(
                                  "${touchedSpot.y.round()} ${getUnitStr(UnitType.vario)}",
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                );
                              }).toList();
                            })),
                            titlesData: const FlTitlesData(
                                leftTitles: AxisTitles(
                                    sideTitleAlignment: SideTitleAlignment.inside,
                                    drawBelowEverything: false,
                                    sideTitles: SideTitles(
                                        showTitles: true, minIncluded: false, reservedSize: 40, maxIncluded: false)),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))))),

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
                                  TextSpan(text: "\u{0078}\u{0304}  ", style: TextStyle(fontWeight: FontWeight.bold)),
                                  richValue(
                                      UnitType.vario,
                                      (logView.samples.last.alt - logView.samples.first.alt) /
                                          logView.timeRange.duration.inSeconds)
                                ])),
                              ],
                            ),
                          ),
                        ))
                  ],
                ))
            ],
          );
        });
  }
}
