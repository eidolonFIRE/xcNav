import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:xcnav/models/flight_log.dart';

class LogStat {
  int numFlights = 0;
  Duration sumDuration = const Duration();
  double sumDist = 0;
}

enum ChartLogAggregateMode {
  week,
  year,
}

class ChartLogAggregate extends StatelessWidget {
  ChartLogAggregate({Key? key, required this.logs, required this.mode}) : super(key: key);

  final Iterable<FlightLog> logs;
  final ChartLogAggregateMode mode;
  final Map<int, LogStat> totals = {};

  final _dayLexical = {
    1: "Sun",
    2: "Mon",
    3: "Tue",
    4: "Wed",
    5: "Thu",
    6: "Fri",
    7: "Sat",
  };

  final _monthLexical = {
    1: "Jan",
    2: "Feb",
    3: "Mar",
    4: "Apr",
    5: "May",
    6: "Jun",
    7: "Jul",
    8: "Aug",
    9: "Sep",
    10: "Oct",
    11: "Nov",
    12: "Dec",
  };

  Map<int, String> get lexical => mode == ChartLogAggregateMode.week ? _dayLexical : _monthLexical;

  /// Match if key is same as now.month or now.day depending on chart mode
  bool isKeyMatchNow(int x) {
    switch (mode) {
      case ChartLogAggregateMode.week:
        return DateTime.now().weekday == x;
      case ChartLogAggregateMode.year:
        return DateTime.now().month == x;
    }
  }

  void buildTotals() {
    for (int x = 1; x <= lexical.length; x++) {
      totals[x] = LogStat();
    }
    for (final each in logs) {
      int index = 0;
      switch (mode) {
        case ChartLogAggregateMode.week:
          index = each.startTime.weekday;
          break;
        case ChartLogAggregateMode.year:
          index = each.startTime.month;
          break;
      }

      totals[index]!.numFlights++;
      totals[index]!.sumDist += each.durationDist;
      totals[index]!.sumDuration += each.durationTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    buildTotals();
    return BarChart(
      BarChartData(
        gridData: FlGridData(drawVerticalLine: false),
        barGroups: lexical
            .map((key, value) => MapEntry(
                key,
                BarChartGroupData(x: key, barRods: [
                  BarChartRodData(toY: totals[key]!.numFlights.toDouble(), color: Colors.blue),
                  BarChartRodData(toY: totals[key]!.sumDuration.inMinutes / 60, color: Colors.amber)
                ])))
            .values
            .toList(),
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
                    child: Text(
                      lexical[value.round()] ?? "",
                      style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(
                          fontWeight: isKeyMatchNow(value.round()) ? FontWeight.bold : null,
                          color: isKeyMatchNow(value.round()) ? Colors.redAccent : null)),
                    ),
                  );
                },
              ),
            ),
            rightTitles: AxisTitles(
                axisNameWidget: const Text(
                  "Duration (hr)",
                  style: TextStyle(color: Colors.amber),
                ),
                sideTitles: SideTitles(
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 4,
                      child: Text(value.toStringAsFixed((value % 1).abs() < 0.2 ? 0 : 1))),
                  showTitles: true,
                  // interval: 1,
                  reservedSize: 30,
                )),
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
                        child: Text(value.toStringAsFixed((value % 1).abs() < 0.2 ? 0 : 1))),
                    showTitles: true,
                    reservedSize: 30))),
      ),
    );
  }
}
