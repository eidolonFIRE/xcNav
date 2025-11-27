import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:xcnav/models/log_view.dart';
import 'package:xcnav/peak_detector.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

class GForcePages extends StatelessWidget {
  final void Function(int page) onPageChanged;
  final void Function(double? time)? onSelectedTime;
  final LogView logView;
  const GForcePages(
      {super.key,
      required this.onPageChanged,
      required this.transformController,
      required this.logView,
      this.onSelectedTime});
  final TransformationController transformController;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: logView,
            builder: (context, setStateInner) {
              final slice = logView.gForceSamples;

              final keyPoints = logView.timeRange.duration < Duration(minutes: 5)
                  ? PeakDetectorResult.fromValues(slice)
                  : PeakDetectorResult.fromValues([]);

              final peakStats = PeakStatsResult.fromPeaks(keyPoints);

              final peaksData = LineChartBarData(
                  show: true,
                  spots: keyPoints.peaks.map((a) => FlSpot(a.time.toDouble(), a.value)).toList(),
                  dotData: FlDotData(
                    getDotPainter: (p0, p1, p2, p3) => FlDotCirclePainter(radius: 3, color: Colors.red),
                  ),
                  isCurved: false,
                  barWidth: 1,
                  color: Colors.red);
              final valleysData = LineChartBarData(
                show: true,
                spots: keyPoints.valleys.map((a) => FlSpot(a.time.toDouble(), a.value)).toList(),
                isCurved: false,
                barWidth: 1,
                color: Colors.blue,
                dotData: FlDotData(
                  getDotPainter: (p0, p1, p2, p3) => FlDotCirclePainter(radius: 3, color: Colors.blue),
                ),
              );

              final maxG = slice.map((e) => e.value).max;
              final maxInt = max(2, (maxG + 0.2).ceil());
              // final double timeInterval =
              //     max(2000, (timeRange.duration.inMilliseconds / 1000).round() * 200);

              return Stack(
                children: [
                  LineChart(
                      transformationConfig: FlTransformationConfig(
                          scaleAxis: FlScaleAxis.horizontal,
                          transformationController: transformController,
                          maxScale: 300),
                      LineChartData(
                          minY: 0,
                          maxY: maxInt.toDouble(),
                          lineTouchData: LineTouchData(
                            touchSpotThreshold: 20,
                            touchTooltipData: LineTouchTooltipData(getTooltipItems: (List<LineBarSpot> touchedSpots) {
                              WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
                                onSelectedTime?.call(touchedSpots[0].x);
                              });
                              return touchedSpots.map((LineBarSpot touchedSpot) {
                                if (touchedSpot.barIndex == 1) {
                                  return LineTooltipItem(
                                    touchedSpot.y.toStringAsFixed(1),
                                    const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                                  );
                                } else if (touchedSpot.barIndex == 2) {
                                  return LineTooltipItem(
                                    touchedSpot.y.toStringAsFixed(1),
                                    const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                                  );
                                }
                                return null;
                              }).toList();
                            }),
                            getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                              return spotIndexes.map((spotIndex) {
                                if (peaksData.spots.isNotEmpty && barData.spots[0] == peaksData.spots[0]) {
                                  return TouchedSpotIndicatorData(const FlLine(color: Colors.red, strokeWidth: 2),
                                      FlDotData(getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                        radius: 3, color: Colors.redAccent, strokeWidth: 2, strokeColor: Colors.red);
                                  }));
                                } else if (valleysData.spots.isNotEmpty && barData.spots[0] == valleysData.spots[0]) {
                                  return TouchedSpotIndicatorData(const FlLine(color: Colors.blue, strokeWidth: 2),
                                      FlDotData(getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                        radius: 3, color: Colors.lightBlue, strokeWidth: 2, strokeColor: Colors.blue);
                                  }));
                                } else {
                                  return const TouchedSpotIndicatorData(
                                    FlLine(color: Colors.transparent),
                                    FlDotData(show: false),
                                  );
                                }
                              }).toList();
                            },
                          ),
                          lineBarsData: [
                            LineChartBarData(
                                spots:
                                    logView.log.gForceSamples.map((a) => FlSpot(a.time.toDouble(), a.value)).toList(),
                                isCurved: true,
                                barWidth: 1,
                                color: Colors.white,
                                dotData: const FlDotData(show: false),
                                aboveBarData:
                                    BarAreaData(color: Colors.blue, show: true, cutOffY: 1, applyCutOffY: true),
                                belowBarData: BarAreaData(
                                    gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        stops: [1 / maxInt, 3 / maxInt, 7 / maxInt],
                                        colors: const [Colors.green, Colors.amber, Colors.red]),
                                    show: true,
                                    color: Colors.amber,
                                    cutOffY: 1,
                                    applyCutOffY: true)),
                            peaksData,
                            valleysData,
                          ],
                          gridData: FlGridData(
                              drawVerticalLine: true,
                              drawHorizontalLine: true,
                              horizontalInterval: maxInt > 3 ? 1 : 0.5,
                              verticalInterval: verticalLineInterval(logView.timeRange.duration)),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                  maxIncluded: false,
                                  // interval: timeInterval,
                                  getTitlesWidget: (value, meta) => Text.rich(richMinSec(
                                      duration: Duration(
                                          milliseconds: value.round() -
                                              logView.log.gForceSamples[logView.gForceIndexRange.start].time))),
                                  showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitleAlignment: SideTitleAlignment.inside,
                              drawBelowEverything: false,
                              sideTitles: SideTitles(
                                  interval: maxInt > 3 ? 1 : 0.5,
                                  showTitles: true,
                                  reservedSize: 40,
                                  maxIncluded: false,
                                  minIncluded: false),
                            ),
                          ))),

                  // --- Stats - bottom
                  if ((keyPoints.peaks.isNotEmpty || keyPoints.valleys.isNotEmpty))
                    Align(
                        alignment: Alignment.bottomRight,
                        child: Card(
                          margin: EdgeInsets.zero,
                          color: Colors.grey.shade800.withAlpha(100),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (keyPoints.peaks.isNotEmpty)
                                  Text.rich(TextSpan(children: [
                                    TextSpan(
                                        text: "\u{0078}\u{0304}",
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                    TextSpan(
                                        text: "  ${keyPoints.peaks.map((e) => e.value).average.toStringAsFixed(1)}G"),
                                    TextSpan(text: " ± ${(peakStats.sdPeak).toStringAsFixed(1)}G")
                                  ])),
                                if (peakStats.meanPeriod.isFinite && peakStats.meanPeriod > 0)
                                  Text.rich(TextSpan(children: [
                                    TextSpan(text: "λ", style: TextStyle(fontWeight: FontWeight.bold)),
                                    TextSpan(text: "  ${(peakStats.meanPeriod).toStringAsFixed(1)}s"),
                                    TextSpan(text: " ± ${(peakStats.sdPeriod).toStringAsFixed(1)}s")
                                  ])),
                                if (keyPoints.valleys.isNotEmpty)
                                  Text.rich(TextSpan(children: [
                                    TextSpan(
                                        text: "\u{0078}\u{0304}",
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                    TextSpan(
                                        text: "  ${keyPoints.valleys.map((e) => e.value).average.toStringAsFixed(1)}G"),
                                    TextSpan(text: " ± ${(peakStats.sdValley).toStringAsFixed(1)}G")
                                  ])),
                              ],
                            ),
                          ),
                        )),

                  // --- Stats - top
                  if ((keyPoints.peaks.isNotEmpty || keyPoints.valleys.isNotEmpty))
                    Align(
                        alignment: Alignment.topRight,
                        child: Card(
                          margin: EdgeInsets.zero,
                          color: Colors.grey.shade800.withAlpha(100),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                if (keyPoints.peaks.isNotEmpty)
                                  Text.rich(TextSpan(children: [
                                    WidgetSpan(
                                        child: Icon(
                                      Icons.vertical_align_top,
                                      size: 16,
                                      color: Colors.red,
                                    )),
                                    TextSpan(text: "  ${keyPoints.peaks.map((e) => e.value).max.toStringAsFixed(1)}G"),
                                  ])),
                                if (keyPoints.valleys.isNotEmpty)
                                  Text.rich(TextSpan(children: [
                                    WidgetSpan(
                                        child: Icon(
                                      Icons.vertical_align_bottom,
                                      size: 16,
                                      color: Colors.blue,
                                    )),
                                    TextSpan(
                                        text: "  ${keyPoints.valleys.map((e) => e.value).min.toStringAsFixed(1)}G"),
                                  ])),
                              ],
                            ),
                          ),
                        ))
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ListenableBuilder(
              listenable: logView,
              builder: (context, _) {
                final page = nearestIndex(
                    logView.log.gForceEvents
                        .map((e) => e.timeRange.start.millisecondsSinceEpoch + e.timeRange.duration.inMilliseconds / 2)
                        .toList(),
                    logView.timeRange.start.millisecondsSinceEpoch + logView.timeRange.duration.inMilliseconds / 2);
                return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: logView.log.gForceEvents
                        .mapIndexed((i, e) => Listener(
                            onPointerDown: (_) => onPageChanged(i),
                            child: Container(
                              width: logView.log.gForceEvents.length > 10 ? 20 : 30,
                              height: logView.log.gForceEvents.length > 10 ? 20 : 30,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white, width: i == page ? 3 : 0),
                                color: gradientInterp(
                                    const <Color>[Colors.green, Colors.amber, Colors.red],
                                    const [2, 4, 7],
                                    logView.log.gForceSamples
                                        .sublist(logView.log.gForceEvents[i].gForceIndeces.start,
                                            logView.log.gForceEvents[i].gForceIndeces.end)
                                        .map((e) => e.value)
                                        .max),
                                borderRadius: const BorderRadius.all(Radius.circular(8)),
                              ),
                            )))
                        .toList());
              }),
        ),
        const SizedBox(
          height: 20,
        )
      ],
    );
  }
}
