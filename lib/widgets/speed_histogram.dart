import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

class SpeedHistogram extends StatelessWidget {
  final FlightLog log;
  final ValueNotifier<Range<int>> selectedIndexRange;

  const SpeedHistogram({
    super.key,
    required this.log,
    required this.selectedIndexRange,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
        valueListenable: selectedIndexRange,
        builder: (context, range, _) {
          final maxX = log.speedHistMaxIndex;
          final hist = log.speedHistogram(range.start, range.end, width: maxX);

          return LineChart(LineChartData(
              borderData: FlBorderData(show: false),
              // barTouchData: BarTouchData(enabled: false),
              minY: 0,
              maxX: maxX.toDouble() - 1,
              lineTouchData: LineTouchData(enabled: false),
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
                        .mapIndexed((i, e) => FlSpot((i + hist.range.start).toDouble(), e.toDouble()))
                        .toList())
              ],
              gridData: FlGridData(drawVerticalLine: true, drawHorizontalLine: false, verticalInterval: 2),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  axisNameWidget: Text(getUnitStr(UnitType.speed)),
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 2,
                    reservedSize: 30,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      return
                          // (unitConverters[UnitType.speed]!(value).round() % 5 == 0)
                          // ?
                          SideTitleWidget(
                        meta: meta,
                        child: Text(
                          "${unitConverters[UnitType.speed]!(value).round() + hist.range.start}",
                        ),
                      );
                      // : Container();
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              )));
        });
  }
}
