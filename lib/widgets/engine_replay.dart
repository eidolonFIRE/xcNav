import 'dart:math';

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xcnav/models/log_view.dart';
import 'package:xcnav/trendlines.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

class EngineReplay extends StatelessWidget {
  final LogView logView;
  final void Function(double? time)? onSelectedTime;
  final String rpmSource;
  final bool hasSp140;
  final TransformationController transformController;

  const EngineReplay({
    super.key,
    required this.logView,
    this.onSelectedTime,
    required this.rpmSource,
    this.hasSp140 = false,
    required this.transformController,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: logView,
        builder: (context, _) {
          final rpmDataFull = hasSp140
              ? logView.log.getBleDeviceSeries(rpmSource, "power")
              : logView.log.getBleDeviceSeries(rpmSource, "rpm").where((e) => e.value > 2000).toList();
          final rpmData = hasSp140
              ? logView.getBleDeviceSeries(rpmSource, "power")
              : logView.getBleDeviceSeries(rpmSource, "rpm").where((e) => e.value > 2000).toList();
          if (rpmData.isEmpty) {
            return Center(child: Text("No Data".tr()));
          }
          final rpmVario = logView.varioLogSmoothed
              .map((each) => Point<double>(
                  rpmData[nearestIndex(rpmData.map((e) => e.time.toDouble()).toList(), each.time.toDouble())].value,
                  unitConverters[UnitType.vario]!(each.value)))
              .sorted((a, b) => (a.x - b.x).round())
              .toList();

          if (rpmVario.isEmpty) {
            return Center(child: Text("No Data".tr()));
          }

          String yUnit = hasSp140 ? "kW" : "RPM".tr();

          final rpmVarioTrend =
              getLinearTrendlineTuned(values: rpmVario, outlierThresh: hasSp140 ? 200 : 100, iterations: 2);

          return Column(
            children: [
              Expanded(
                flex: 2,
                child: Stack(
                  children: [
                    Align(
                        alignment: Alignment.topLeft,
                        child: Text("${"gear.Engine".tr()} $yUnit", style: TextStyle(color: Colors.grey))),
                    LineChart(
                        transformationConfig: FlTransformationConfig(
                            scaleAxis: FlScaleAxis.horizontal,
                            transformationController: transformController,
                            maxScale: 300),
                        LineChartData(
                            gridData: FlGridData(verticalInterval: verticalLineInterval(logView.timeRange.duration)),
                            clipData: FlClipData.horizontal(),
                            lineTouchData: LineTouchData(
                                getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                              return spotIndexes.map((spotIndex) {
                                if (barData.spots[0].y == rpmDataFull.first.value) {
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
                                  "${touchedSpots[0].y.round()}",
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ];
                            })),
                            lineBarsData: [
                              LineChartBarData(
                                  spots: rpmDataFull.map((e) => FlSpot(e.time.toDouble(), e.value)).toList(),
                                  barWidth: 1,
                                  dotData: const FlDotData(show: false),
                                  color: Colors.lightGreenAccent,
                                  belowBarData: BarAreaData(
                                    show: true,
                                    gradient: LinearGradient(
                                        colors: [Colors.lightGreen, Colors.lightGreen.withAlpha(50)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter),
                                  )),
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
                                    Icons.vertical_align_top,
                                    size: 18,
                                  )),
                                  TextSpan(text: rpmData.map((e) => e.value).toList().max.round().toString()),
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
              // --- RPM / Vario plot
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    Align(
                        alignment: Alignment.topLeft,
                        child: Text("${"Vario".tr()} / $yUnit", style: TextStyle(color: Colors.grey))),
                    LineChart(LineChartData(
                        clipData: FlClipData.all(),
                        lineTouchData: LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                              spots: rpmVario
                                  .map((each) => ScatterSpot(
                                        each.x,
                                        each.y,
                                      ))
                                  .toList(),
                              barWidth: 0,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (spot, value, data, i) {
                                  return FlDotCirclePainter(
                                      radius: 3,
                                      strokeWidth: 0,
                                      color: Colors.lightGreenAccent
                                          .withAlpha(min(255, max(1.0, 30000.0 / rpmData.length.toDouble()).round())));
                                },
                              )),
                          // --- Trendline
                          LineChartBarData(
                              spots: rpmVarioTrend.points
                                  .map((each) => ScatterSpot(
                                        each.x,
                                        each.y,
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
                                sideTitles: SideTitles(
                                    showTitles: true, minIncluded: false, maxIncluded: false, reservedSize: 40)),
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
                                      child: SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: SvgPicture.asset("assets/images/zero_crossing.svg"))),
                                  TextSpan(text: " ${(-rpmVarioTrend.offset / rpmVarioTrend.slope).round()}"),
                                ])),
                              ],
                            ),
                          ),
                        ))
                  ],
                ),
              )
            ],
          );
        });
  }
}
