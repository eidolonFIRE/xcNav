import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

class ElevationReplay extends StatelessWidget {
  final FlightLog log;
  final ValueNotifier<Range<int>> selectedIndexRange;
  final void Function(int index)? onSelectedGForce;

  final bool showVario;

  const ElevationReplay({
    super.key,
    required this.log,
    required this.showVario,
    required this.selectedIndexRange,
    this.onSelectedGForce,
  });

  @override
  Widget build(BuildContext context) {
    final logGForceIndeces =
        log.gForceEvents.map((e) => log.timeToSampleIndex(DateTime.fromMillisecondsSinceEpoch(e.center.time))).toList();

    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder(
              valueListenable: selectedIndexRange,
              builder: (context, range, _) {
                return LineChart(
                  LineChartData(
                      clipData: FlClipData.horizontal(),
                      minX: log.samples[range.start].time.toDouble(),
                      maxX: log.samples[range.end].time.toDouble(),
                      minY: unitConverters[UnitType.distFine]!(min(
                          log.samples.map((e) => e.alt).min - 10, log.samples.map((e) => e.ground).nonNulls.min - 10)),
                      lineTouchData: LineTouchData(
                        handleBuiltInTouches: false,
                        getTouchedSpotIndicator: (barData, spotIndexes) => spotIndexes
                            .map(
                                (e) => TouchedSpotIndicatorData(const FlLine(strokeWidth: 0), FlDotData(getDotPainter: (
                                      FlSpot spot,
                                      double xPercentage,
                                      LineChartBarData bar,
                                      int index, {
                                      double? size,
                                    }) {
                                      return FlDotCirclePainter(
                                        radius: size ?? 5,
                                        color: Colors.amber,
                                        strokeColor: Colors.grey,
                                      );
                                    })))
                            .toList(),
                        touchCallback: (p0, p1) {
                          if (p0 is FlTapUpEvent) {
                            final index = p1?.lineBarSpots?.first.spotIndex;
                            if (index != null) {
                              List<int> dist = [];
                              for (final each in logGForceIndeces) {
                                dist.add((index - each).abs());
                              }
                              final closest = dist.min;
                              final closestIndex = dist.indexOf(closest);
                              if (closest < log.samples.length / 10) {
                                // Go to g-force
                                onSelectedGForce?.call(closestIndex);
                              }
                            }
                          }
                        },
                      ),
                      lineBarsData: [
                            LineChartBarData(
                                barWidth: 0,
                                dotData: const FlDotData(show: false),
                                spots: log.samples
                                    .where((e) => e.ground != null)
                                    .map(
                                        (e) => FlSpot(e.time.toDouble(), unitConverters[UnitType.distFine]!(e.ground!)))
                                    .toList(),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: const Color.fromARGB(255, 133, 81, 39),
                                )),
                            LineChartBarData(
                                showingIndicators: logGForceIndeces,
                                spots: log.samples
                                    .map((e) => FlSpot(e.time.toDouble(), unitConverters[UnitType.distFine]!(e.alt)))
                                    .toList(),
                                barWidth: 2,
                                dotData: const FlDotData(show: false),
                                color: Colors.blue),
                          ] +
                          log.gForceEvents
                              .mapIndexed((i, e) => LineChartBarData(
                                  color: Colors.amber,
                                  barWidth: 2,
                                  dotData: const FlDotData(show: false),
                                  spots: log.samples
                                      .sublist(
                                          log.timeToSampleIndex(DateTime.fromMillisecondsSinceEpoch(
                                              e.timeRange.start.millisecondsSinceEpoch)),
                                          log.timeToSampleIndex(DateTime.fromMillisecondsSinceEpoch(
                                              e.timeRange.end.millisecondsSinceEpoch)))
                                      .map((e) => FlSpot(e.time.toDouble(), unitConverters[UnitType.distFine]!(e.alt)))
                                      .toList()))
                              .toList(),
                      titlesData: const FlTitlesData(
                          leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: true, minIncluded: false, reservedSize: 40)),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)))),
                );
              }),
        ),
        Container(
          height: 10,
        ),
        if (showVario)
          Expanded(
              child: ValueListenableBuilder(
                  valueListenable: selectedIndexRange,
                  builder: (context, range, _) {
                    return LineChart(LineChartData(
                        clipData: FlClipData.horizontal(),
                        minX: log.samples[range.start].time.toDouble(),
                        maxX: log.samples[range.end].time.toDouble(),
                        lineBarsData: [
                          LineChartBarData(
                            aboveBarData: BarAreaData(show: true, color: Colors.amber, applyCutOffY: true, cutOffY: 0),
                            belowBarData: BarAreaData(show: true, color: Colors.green, applyCutOffY: true, cutOffY: 0),
                            dotData: FlDotData(show: false),
                            barWidth: 1,
                            color: Colors.white,
                            spots: log.varioLogSmoothed
                                .map((e) => FlSpot(e.time.toDouble(), unitConverters[UnitType.vario]!(e.value)))
                                .toList(),
                          )
                        ],
                        lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (List<LineBarSpot> touchedSpots) =>
                                    touchedSpots.map((LineBarSpot touchedSpot) {
                                      return LineTooltipItem(
                                        touchedSpot.y.toStringAsFixed(1),
                                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      );
                                    }).toList())),
                        titlesData: const FlTitlesData(
                            leftTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: true, minIncluded: false, reservedSize: 40)),
                            topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)))));
                  }))
      ],
    );
  }
}
