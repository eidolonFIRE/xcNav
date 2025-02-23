import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:xcnav/douglas_peucker.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';

class GForcePages extends StatelessWidget {
  final FlightLog log;
  final void Function(int page) onPageChanged;
  final PageController pageController;
  const GForcePages({super.key, required this.log, required this.onPageChanged, required this.pageController});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: PageView.builder(
              controller: pageController,
              itemCount: log.gForceEvents.length,
              onPageChanged: (int index) {
                onPageChanged(index);
              },
              itemBuilder: (context, index) {
                bool showPeaks = false;
                return StatefulBuilder(
                  builder: (context, setStateInner) {
                    final slice = log.gForceSamples
                        .sublist(log.gForceEvents[index].gForceIndeces.start, log.gForceEvents[index].gForceIndeces.end)
                        .toList();
                    final keyPoints = douglasPeuckerTimestamped(slice, 0.3).toList();

                    final peaksData = LineChartBarData(
                        show: showPeaks,
                        spots: keyPoints
                            .whereIndexed((i, e) =>
                                i < keyPoints.length - 1 &&
                                i > 0 &&
                                e.value > keyPoints[i - 1].value &&
                                e.value > keyPoints[i + 1].value)
                            .map((a) => FlSpot(a.time.toDouble(), a.value))
                            .toList(),
                        dotData: FlDotData(
                          getDotPainter: (p0, p1, p2, p3) => FlDotCirclePainter(radius: 3, color: Colors.red),
                        ),
                        isCurved: false,
                        barWidth: 1,
                        color: Colors.red);
                    final valleysData = LineChartBarData(
                      show: showPeaks,
                      spots: keyPoints
                          .whereIndexed((i, e) =>
                              i < keyPoints.length - 1 &&
                              i > 0 &&
                              e.value < keyPoints[i - 1].value &&
                              e.value < keyPoints[i + 1].value)
                          .map((a) => FlSpot(a.time.toDouble(), a.value))
                          .toList(),
                      isCurved: false,
                      barWidth: 1,
                      color: Colors.blue,
                      dotData: FlDotData(
                        getDotPainter: (p0, p1, p2, p3) => FlDotCirclePainter(radius: 3, color: Colors.blue),
                      ),
                    );

                    final maxG = log.maxG(index: index);
                    final maxInt = (maxG + 0.5).ceil();
                    final double timeInterval =
                        max(2000, (log.gForceEvents[index].timeRange.duration.inMilliseconds / 1000).round() * 200);

                    return GestureDetector(
                      onLongPressDown: (details) {
                        setStateInner(() => showPeaks = true);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Builder(builder: (context) {
                          return LineChart(LineChartData(
                              minY: 0,
                              maxY: maxInt.toDouble(),
                              extraLinesData: ExtraLinesData(horizontalLines: [
                                if (maxG > 1.5)
                                  HorizontalLine(
                                      label: HorizontalLineLabel(
                                        show: true,
                                        labelResolver: (p0) => "Max ${maxG.toStringAsFixed(1)}G",
                                      ),
                                      y: maxG,
                                      color: Colors.white,
                                      strokeWidth: 1),
                              ]),
                              borderData: FlBorderData(show: false),
                              lineTouchData: LineTouchData(
                                touchSpotThreshold: 20,
                                touchTooltipData: LineTouchTooltipData(
                                    getTooltipItems: (List<LineBarSpot> touchedSpots) =>
                                        touchedSpots.map((LineBarSpot touchedSpot) {
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
                                        }).toList()),
                                getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                                  return spotIndexes.map((spotIndex) {
                                    if (barData.spots[0] == peaksData.spots[0]) {
                                      return TouchedSpotIndicatorData(const FlLine(color: Colors.red, strokeWidth: 2),
                                          FlDotData(getDotPainter: (spot, percent, barData, index) {
                                        return FlDotCirclePainter(
                                            radius: 3,
                                            color: Colors.redAccent,
                                            strokeWidth: 2,
                                            strokeColor: Colors.red);
                                      }));
                                    } else if (barData.spots[0] == valleysData.spots[0]) {
                                      return TouchedSpotIndicatorData(const FlLine(color: Colors.blue, strokeWidth: 2),
                                          FlDotData(getDotPainter: (spot, percent, barData, index) {
                                        return FlDotCirclePainter(
                                            radius: 3,
                                            color: Colors.blueAccent,
                                            strokeWidth: 2,
                                            strokeColor: Colors.blue);
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
                                    spots: slice.map((a) => FlSpot(a.time.toDouble(), a.value)).toList(),
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
                                  horizontalInterval: 1,
                                  verticalInterval: timeInterval / 2),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                      maxIncluded: false,
                                      interval: timeInterval,
                                      getTitlesWidget: (value, meta) => Text.rich(richMinSec(
                                          duration: Duration(
                                              milliseconds: value.round() -
                                                  log.gForceSamples[log.gForceEvents[index].gForceIndeces.start]
                                                      .time))),
                                      showTitles: true),
                                ),
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                leftTitles: const AxisTitles(
                                  sideTitles: SideTitles(interval: 1, showTitles: true),
                                ),
                              )));
                        }),
                      ),
                    );
                  },
                );
              }),
        ),
        SmoothPageIndicator(
          controller: pageController,
          count: log.gForceEvents.length,
          effect: const SlideEffect(activeDotColor: Colors.white),
          onDotClicked: (index) => pageController.jumpToPage(index),
        ),
        const SizedBox(
          height: 20,
        )
      ],
    );
  }
}
