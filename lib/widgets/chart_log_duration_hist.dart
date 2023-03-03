import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';

class LogStatHist {
  int dur = 0;
  int dist = 0;
}

class ChartLogDurationHist extends StatelessWidget {
  ChartLogDurationHist({Key? key, required this.logs}) : super(key: key);

  final Iterable<FlightLog> logs;
  final Map<int, LogStatHist> totals = {};

  int roundDuration(Duration input, Duration size) {
    return (input.inSeconds / size.inSeconds).round();
  }

  void buildTotals(Duration longest, Duration bucketSizeDur) {
    totals.clear();
    for (int t = 0; t <= longest.inSeconds / bucketSizeDur.inSeconds + 1; t++) {
      totals[t] = LogStatHist();
    }
    for (final each in logs) {
      int index = roundDuration(each.durationTime, bucketSizeDur);
      if (totals.containsKey(index)) {
        totals[index]!.dur++;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Duration longest =
        maxBy<Duration, int>(logs.map((e) => e.durationTime), (e) => e.inSeconds) ?? const Duration(hours: 1);
    Duration bucketSizeDur = Duration(minutes: max(5, min(15, 5 * (1 / logs.length * longest.inMinutes).ceil())));
    buildTotals(longest, bucketSizeDur);
    return LineChart(
      LineChartData(
        gridData: FlGridData(verticalInterval: 1),
        minY: 0,
        lineBarsData: [
          LineChartBarData(
              barWidth: 4,
              isCurved: true,
              preventCurveOverShooting: true,
              // preventCurveOvershootingThreshold: 0,
              dotData: FlDotData(show: false),
              color: Colors.blue,
              spots: totals
                  .map((key, value) => MapEntry(key, FlSpot(key.toDouble(), value.dur.toDouble())))
                  .values
                  .toList())
        ],
        titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (double value, TitleMeta meta) {
                  return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 10,
                      angle: -45,
                      child: Text.rich(
                        TextSpan(children: [
                          richHrMin(
                              duration: Duration(seconds: (value * bucketSizeDur.inSeconds).round()),
                              unitStyle: Theme.of(context)
                                  .textTheme
                                  .bodyMedium!
                                  .merge(const TextStyle(color: Colors.grey, fontSize: 10)))
                        ]),
                      ));
                },
              ),
            ),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
                axisNameWidget: const Text(
                  "Flights",
                  style: TextStyle(color: Colors.blue),
                ),
                sideTitles: SideTitles(
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                        axisSide: meta.axisSide, space: 4, child: Text("${(value / logs.length * 100).round()}%")),
                    showTitles: true,
                    reservedSize: 30))),
      ),
    );
  }
}
