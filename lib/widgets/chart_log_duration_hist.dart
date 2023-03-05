import 'dart:math';

import 'package:bisection/bisect.dart';
import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';

class LogStatHist {
  Duration x;
  int y = 0;

  LogStatHist(this.x);
}

class ChartLogDurationHist extends StatelessWidget {
  final Iterable<FlightLog> logs;
  final List<LogStatHist> totals = [];
  late final Duration longest;
  final Duration baseScale = const Duration(minutes: 5);

  ChartLogDurationHist({Key? key, required this.logs}) : super(key: key) {
    longest = maxBy<Duration, int>(logs.map((e) => e.durationTime), (e) => e.inSeconds) ?? const Duration(hours: 1);
    // bucketSizeDur = Duration(minutes: max(5, min(15, 5 * (1 / logs.length * longest.inMinutes).ceil())));
    buildTotals(logs.map((e) => e.durationTime));
  }

  int toIndex(Duration value) {
    // find segment
    final int insertIndex = bisect_left(totals.map((e) => e.x).toList(), value);
    if (insertIndex <= 0) {
      return 0;
    } else if (insertIndex >= totals.length) {
      // overflow
      return totals.length;
    } else {
      // snap to nearest
      return (value - totals[insertIndex - 1].x < totals[insertIndex].x - value) ? insertIndex - 1 : insertIndex;
    }
  }

  Duration nextInterval(int index) {
    /// I tried some algorithms to replace this, but turns out this is simpler and more performant. \shrug
    int interval(int t) {
      if (t < 4) {
        return 10;
      } else if (t < 10) {
        return 15;
      } else {
        return 30;
      }
    }

    if (index == 0) {
      return const Duration();
    } else {
      return totals[index - 1].x + Duration(minutes: interval(index));
    }
  }

  void buildTotals(Iterable<Duration> data) {
    totals.add(LogStatHist(nextInterval(totals.length)));

    for (final each in data) {
      int index = toIndex(each);
      while (index >= totals.length) {
        // build out more indeces
        totals.add(LogStatHist(nextInterval(totals.length)));
        index = toIndex(each);
      }

      if (totals.length > index) {
        totals[index].y++;
      } else {
        debugPrint("OVERFLOW!");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: FlGridData(verticalInterval: 1),
        minY: 0,
        lineBarsData: [
          LineChartBarData(
              barWidth: 4,
              isCurved: true,
              preventCurveOverShooting: true,
              dotData: FlDotData(show: false),
              color: Colors.blue,
              spots: totals.mapIndexed((index, value) => FlSpot(index.toDouble(), value.y.toDouble())).toList())
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
                              duration: totals[value.round()].x,
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
                        axisSide: meta.axisSide,
                        space: 4,
                        child: Text("${(value / max(1, logs.length) * 100).round()}%")),
                    showTitles: true,
                    reservedSize: 30))),
      ),
    );
  }
}
