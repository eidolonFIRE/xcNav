import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/peak_detector.dart';
import 'package:xcnav/units.dart';

class GForcePages extends StatefulWidget {
  final FlightLog log;
  final void Function(int page) onPageChanged;
  final PageController pageController;
  const GForcePages({super.key, required this.log, required this.onPageChanged, required this.pageController});

  @override
  State<GForcePages> createState() => _GForcePagesState();
}

class _GForcePagesState extends State<GForcePages> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: PageView.builder(
              controller: widget.pageController,
              itemCount: widget.log.gForceEvents.length,
              onPageChanged: (int index) {
                widget.onPageChanged(index);
              },
              itemBuilder: (context, index) {
                bool showPeaks = false;
                return StatefulBuilder(
                  builder: (context, setStateInner) {
                    final slice = widget.log.gForceSamples
                        .sublist(widget.log.gForceEvents[index].gForceIndeces.start,
                            widget.log.gForceEvents[index].gForceIndeces.end)
                        .toList();
                    final keyPoints = PeakDetectorResult.fromValues(slice);

                    final peakStats = PeakStatsResult.fromPeaks(keyPoints);

                    final peaksData = LineChartBarData(
                        show: showPeaks,
                        spots: keyPoints.peaks.map((a) => FlSpot(a.time.toDouble(), a.value)).toList(),
                        dotData: FlDotData(
                          getDotPainter: (p0, p1, p2, p3) => FlDotCirclePainter(radius: 3, color: Colors.red),
                        ),
                        isCurved: false,
                        barWidth: 1,
                        color: Colors.red);
                    final valleysData = LineChartBarData(
                      show: showPeaks,
                      spots: keyPoints.valleys.map((a) => FlSpot(a.time.toDouble(), a.value)).toList(),
                      isCurved: false,
                      barWidth: 1,
                      color: Colors.blue,
                      dotData: FlDotData(
                        getDotPainter: (p0, p1, p2, p3) => FlDotCirclePainter(radius: 3, color: Colors.blue),
                      ),
                    );

                    final maxG = widget.log.maxG(index: index);
                    final maxInt = (maxG + 0.8).ceil();
                    final double timeInterval = max(
                        2000, (widget.log.gForceEvents[index].timeRange.duration.inMilliseconds / 1000).round() * 200);

                    return GestureDetector(
                      onLongPressDown: (_) {
                        setStateInner(() => showPeaks = true);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Builder(builder: (context) {
                          return Stack(
                            children: [
                              LineChart(LineChartData(
                                  minY: 0,
                                  maxY: maxInt.toDouble(),
                                  extraLinesData: ExtraLinesData(horizontalLines: [
                                    if (maxG > 1.5 && !showPeaks)
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
                                        if (peaksData.spots.isNotEmpty && barData.spots[0] == peaksData.spots[0]) {
                                          return TouchedSpotIndicatorData(
                                              const FlLine(color: Colors.red, strokeWidth: 2),
                                              FlDotData(getDotPainter: (spot, percent, barData, index) {
                                            return FlDotCirclePainter(
                                                radius: 3,
                                                color: Colors.redAccent,
                                                strokeWidth: 2,
                                                strokeColor: Colors.red);
                                          }));
                                        } else if (valleysData.spots.isNotEmpty &&
                                            barData.spots[0] == valleysData.spots[0]) {
                                          return TouchedSpotIndicatorData(
                                              const FlLine(color: Colors.blue, strokeWidth: 2),
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
                                                      widget
                                                          .log
                                                          .gForceSamples[
                                                              widget.log.gForceEvents[index].gForceIndeces.start]
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
                                  ))),

                              // --- Stats
                              if (showPeaks && (keyPoints.peaks.isNotEmpty || keyPoints.valleys.isNotEmpty))
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
                                            if (keyPoints.peaks.isNotEmpty)
                                              Text.rich(TextSpan(children: [
                                                TextSpan(
                                                    text: "\u{0078}\u{0304}",
                                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                                TextSpan(
                                                    text:
                                                        "   ${keyPoints.peaks.map((e) => e.value).average.toStringAsFixed(1)}G"),
                                                TextSpan(text: " ± ${(peakStats.sdPeak).toStringAsFixed(1)}G")
                                              ])),
                                            if (peakStats.meanPeriod.isFinite && peakStats.meanPeriod > 0)
                                              Text.rich(TextSpan(children: [
                                                TextSpan(text: "λ", style: TextStyle(fontWeight: FontWeight.bold)),
                                                TextSpan(text: "   ${(peakStats.meanPeriod).toStringAsFixed(1)}s"),
                                                TextSpan(text: " ± ${(peakStats.sdPeriod).toStringAsFixed(1)}s")
                                              ])),
                                            if (keyPoints.valleys.isNotEmpty)
                                              Text.rich(TextSpan(children: [
                                                TextSpan(
                                                    text: "\u{0078}\u{0304}",
                                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                                TextSpan(
                                                    text:
                                                        "   ${keyPoints.valleys.map((e) => e.value).average.toStringAsFixed(1)}G"),
                                                TextSpan(text: " ± ${(peakStats.sdValley).toStringAsFixed(1)}G")
                                              ])),
                                          ],
                                        ),
                                      ),
                                    ))
                            ],
                          );
                        }),
                      ),
                    );
                  },
                );
              }),
        ),
        SmoothPageIndicator(
          controller: widget.pageController,
          count: widget.log.gForceEvents.length,
          effect: const SlideEffect(activeDotColor: Colors.white),
          onDotClicked: (index) => widget.pageController.jumpToPage(index),
        ),
        const SizedBox(
          height: 20,
        )
      ],
    );
  }
}
