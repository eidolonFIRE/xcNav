import 'package:easy_localization/easy_localization.dart';
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
  ChartLogAggregate({super.key, required this.logs, required this.mode});

  final Iterable<FlightLog> logs;
  final ChartLogAggregateMode mode;
  final Map<int, LogStat> totals = {};

  final _dayLexical = {
    1: "time.day.short.sun".tr(),
    2: "time.day.short.mon".tr(),
    3: "time.day.short.tue".tr(),
    4: "time.day.short.wed".tr(),
    5: "time.day.short.thu".tr(),
    6: "time.day.short.fri".tr(),
    7: "time.day.short.sat".tr(),
  };

  final _monthLexical = {
    1: "time.month.short.jan".tr(),
    2: "time.month.short.feb".tr(),
    3: "time.month.short.mar".tr(),
    4: "time.month.short.apr".tr(),
    5: "time.month.short.may".tr(),
    6: "time.month.short.jun".tr(),
    7: "time.month.short.jul".tr(),
    8: "time.month.short.aug".tr(),
    9: "time.month.short.sep".tr(),
    10: "time.month.short.oct".tr(),
    11: "time.month.short.nov".tr(),
    12: "time.month.short.dec".tr(),
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

      if (each.startTime == null) continue;

      switch (mode) {
        case ChartLogAggregateMode.week:
          index = each.startTime!.weekday;
          break;
        case ChartLogAggregateMode.year:
          index = each.startTime!.month;
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
        gridData: const FlGridData(drawVerticalLine: false),
        barGroups: lexical
            .map((key, value) => MapEntry(
                key,
                BarChartGroupData(x: key, barRods: [
                  BarChartRodData(toY: totals[key]!.numFlights.toDouble(), color: Colors.blue),
                  BarChartRodData(toY: (totals[key]!.sumDuration.inMinutes / 60 * 10).round() / 10, color: Colors.amber)
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
                    meta: meta,
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
                axisNameWidget: Text(
                  "${"Duration".tr()} (${"time.hour.short.one".tr()})",
                  style: TextStyle(color: Colors.amber),
                ),
                sideTitles: SideTitles(
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta, space: 4, child: Text(value.toStringAsFixed((value % 1).abs() < 0.2 ? 0 : 1))),
                  showTitles: true,
                  // interval: 1,
                  reservedSize: 30,
                )),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
                axisNameWidget: Text(
                  "Flights".tr(),
                  style: TextStyle(color: Colors.blue),
                ),
                sideTitles: SideTitles(
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta, space: 4, child: Text(value.toStringAsFixed((value % 1).abs() < 0.2 ? 0 : 1))),
                    showTitles: true,
                    reservedSize: 30))),
      ),
    );
  }
}
