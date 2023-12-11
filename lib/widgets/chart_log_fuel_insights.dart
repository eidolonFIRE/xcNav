import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/units.dart';

enum ChartFuelModeY {
  rate,
  eff,
}

enum ChartFuelModeX {
  alt,
  altGained,
  spd,
}

class ChartLogFuelInsights extends StatelessWidget {
  const ChartLogFuelInsights({
    Key? key,
    required this.logsSlice,
    required this.chartFuelModeX,
    required this.chartFuelModeY,
  }) : super(key: key);

  final Iterable<FlightLog> logsSlice;
  final ChartFuelModeX chartFuelModeX;
  final ChartFuelModeY chartFuelModeY;

  double getX(FuelStat stat) {
    switch (chartFuelModeX) {
      case ChartFuelModeX.alt:
        return unitConverters[UnitType.distFine]!(stat.meanAlt);
      case ChartFuelModeX.altGained:
        return unitConverters[UnitType.distFine]!(stat.altGained);
      case ChartFuelModeX.spd:
        return unitConverters[UnitType.speed]!(stat.meanSpd);
    }
  }

  double getY(FuelStat stat) {
    switch (chartFuelModeY) {
      case ChartFuelModeY.eff:
        return unitConverters[UnitType.distCoarse]!(stat.mpl / unitConverters[UnitType.fuel]!(1));
      case ChartFuelModeY.rate:
        return unitConverters[UnitType.fuel]!(stat.rate);
    }
  }

  Widget getXunit() {
    switch (chartFuelModeX) {
      case ChartFuelModeX.alt:
        return Text(getUnitStr(UnitType.distFine, lexical: true));
      case ChartFuelModeX.altGained:
        return Text(getUnitStr(UnitType.distFine, lexical: true));
      case ChartFuelModeX.spd:
        return Text(getUnitStr(UnitType.speed));
    }
  }

  Widget getYunit() {
    switch (chartFuelModeY) {
      case ChartFuelModeY.eff:
        return Text(fuelEffStr);
      case ChartFuelModeY.rate:
        return Text(fuelRateStr);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (logsSlice.isNotEmpty) {
      final int cardinalityStats = logsSlice
          .map(
            (e) => e.fuelStats.length,
          )
          .reduce((a, b) => a + b);
      return ScatterChart(ScatterChartData(
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
                axisNameWidget: getYunit(), sideTitles: const SideTitles(showTitles: true, reservedSize: 30)),
            bottomTitles: AxisTitles(
                axisNameWidget: getXunit(), sideTitles: const SideTitles(showTitles: true, reservedSize: 25)),
          ),
          scatterSpots: logsSlice
              .map((e) => e.fuelStats
                  .map((s) => ScatterSpot(getX(s), getY(s),
                      radius: 3 + s.durationTime.inHours.toDouble() * 2,
                      color: Colors.lightGreen.withAlpha(max(max(30, 150 - cardinalityStats),
                          min(255, (255 * s.durationTime.inSeconds / const Duration(hours: 2).inSeconds).round())))))
                  .toList())
              .reduce((a, b) => a + b)));
    } else {
      return const Center(child: Text("No fuel reports have been added..."));
    }
  }
}
