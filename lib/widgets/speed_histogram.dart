import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/models/log_view.dart';
import 'package:xcnav/peak_detector.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

class SpeedHistogram extends StatelessWidget {
  final LogView logView;
  final TransformationController transformController;
  final void Function(double? time)? onSelectedTime;

  const SpeedHistogram({super.key, required this.logView, required this.transformController, this.onSelectedTime});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
              listenable: logView,
              builder: (context, _) {
                return Stack(
                  children: [
                    LineChart(
                        transformationConfig: FlTransformationConfig(
                            scaleAxis: FlScaleAxis.horizontal,
                            transformationController: transformController,
                            maxScale: 300),
                        LineChartData(
                            clipData: FlClipData.horizontal(),
                            maxY: max(
                                30,
                                (logView.samples.map((e) => unitConverters[UnitType.speed]!(e.spd)).max / 10 + 0.5)
                                        .ceil() *
                                    10),
                            minY: 0,
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
                              return [
                                LineTooltipItem(
                                  "${touchedSpots[0].y.round()} ${getUnitStr(UnitType.speed)}",
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ];
                            })),
                            lineBarsData: [
                              LineChartBarData(
                                  barWidth: 1,
                                  color: Colors.cyanAccent,
                                  belowBarData: BarAreaData(
                                    show: true,
                                    // applyCutOffY: false,
                                    gradient: LinearGradient(
                                        colors: [Colors.cyan, Colors.cyan.withAlpha(50)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter),
                                  ),
                                  dotData: const FlDotData(show: false),
                                  spots: logView.log.samples
                                      .map((e) => FlSpot(e.time.toDouble(), unitConverters[UnitType.speed]!(e.spd)))
                                      .toList()),
                            ],
                            gridData: FlGridData(verticalInterval: verticalLineInterval(logView.timeRange.duration)),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(TextSpan(children: [
                                  WidgetSpan(
                                      child: Icon(
                                    Icons.vertical_align_top,
                                    size: 16,
                                  )),
                                  TextSpan(
                                      text:
                                          "  ${logView.samples.map((e) => unitConverters[UnitType.speed]!(e.spd)).max.toStringAsFixed(1)} "),
                                  TextSpan(text: getUnitStr(UnitType.speed)),
                                ])),
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
                              ],
                            ),
                          ),
                        ))
                  ],
                );
              }),
        ),
        Container(
          height: 10,
        ),
        Expanded(
          child: ListenableBuilder(
              listenable: logView,
              builder: (context, _) {
                final maxX = logView.log.speedHistMaxIndex;
                final hist = logView.log
                    .speedHistogram(logView.sampleIndexRange.start, logView.sampleIndexRange.end, width: maxX);
                final peaks = PeakDetectorResult.fromValues(
                    hist.values.mapIndexed((i, v) => TimestampDouble(i * 1000, v.toDouble())).toList(),
                    radius: 1,
                    thresh: hist.values.max / 7,
                    peakThreshold: hist.values.max / 7);

                final peaksData = LineChartBarData(
                    show: true,
                    spots: peaks.peaks
                        .map((a) => FlSpot(
                            unitConverters[UnitType.speed]!(a.time.toDouble() / 2000 + hist.range.start), a.value))
                        .toList(),
                    dotData: FlDotData(
                      getDotPainter: (p0, p1, p2, p3) => FlDotCirclePainter(radius: 3, color: Colors.white),
                    ),
                    isCurved: false,
                    barWidth: 1,
                    color: Colors.white);

                return Stack(
                  children: [
                    LineChart(LineChartData(
                        clipData: FlClipData.all(),

                        // barTouchData: BarTouchData(enabled: false),
                        maxY: hist.values.max * 1.1,
                        minY: 0,
                        maxX: unitConverters[UnitType.speed]!(maxX / 2),
                        lineTouchData: LineTouchData(
                            enabled: true,
                            touchSpotThreshold: 20,
                            touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (List<LineBarSpot> touchedSpots) =>
                                    touchedSpots.map((LineBarSpot touchedSpot) {
                                      if (touchedSpot.barIndex == 1) {
                                        return LineTooltipItem(
                                          touchedSpot.x.toStringAsFixed(1),
                                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        );
                                      } else {
                                        return null;
                                      }
                                    }).toList()),
                            getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                              return spotIndexes.map((spotIndex) {
                                if (peaksData.spots.isNotEmpty && barData.spots[0] == peaksData.spots[0]) {
                                  return TouchedSpotIndicatorData(const FlLine(color: Colors.white, strokeWidth: 2),
                                      FlDotData(getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                        radius: 3, color: Colors.white, strokeWidth: 2, strokeColor: Colors.white);
                                  }));
                                } else {
                                  return null;
                                }
                              }).toList();
                            }),
                        lineBarsData: [
                          LineChartBarData(
                              isCurved: true,
                              dotData: FlDotData(show: false),
                              color: Colors.amber,
                              belowBarData: BarAreaData(
                                show: true,
                                // applyCutOffY: false,
                                gradient: LinearGradient(
                                    colors: [Colors.amber, Colors.amber.withAlpha(50)],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter),
                              ),
                              spots: hist.values
                                  .mapIndexed((i, e) =>
                                      FlSpot(unitConverters[UnitType.speed]!(i / 2 + hist.range.start), e.toDouble()))
                                  .toList()),
                          peaksData,
                        ],
                        gridData: FlGridData(drawVerticalLine: true, drawHorizontalLine: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              maxIncluded: false,
                              showTitles: true,
                              reservedSize: 30,
                            ),
                          ),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ))),

                    // --- Stats
                    if ((peaks.peaks.isNotEmpty || peaks.valleys.isNotEmpty))
                      Align(
                          alignment: Alignment.topLeft,
                          child: Card(
                            margin: EdgeInsets.zero,
                            color: Colors.grey.shade800.withAlpha(100),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (peaks.peaks.length > 1)
                                    Text.rich(TextSpan(children: [
                                      TextSpan(text: "λ", style: TextStyle(fontWeight: FontWeight.bold)),
                                      TextSpan(
                                          text:
                                              "  ${(unitConverters[UnitType.speed]!((peaks.peaks.last.time - peaks.peaks.first.time).toDouble() / 2000 + hist.range.start)).toStringAsFixed(1)} "),
                                      TextSpan(text: getUnitStr(UnitType.speed))
                                    ])),
                                ],
                              ),
                            ),
                          ))
                  ],
                );
              }),
        ),
      ],
    );
  }
}
