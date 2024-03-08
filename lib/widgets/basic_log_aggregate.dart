import 'dart:math';

import 'package:flutter/material.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';

class BasicLogAggregate extends StatelessWidget {
  const BasicLogAggregate({super.key, required this.logs});

  final Iterable<FlightLog> logs;

  @override
  Widget build(BuildContext context) {
    final totalDist = logs.map((e) => e.durationDist).fold<double>(0, (a, b) => a + b);
    final totalDur = logs.map((e) => e.durationTime).fold<Duration>(const Duration(), (a, b) => a + b);
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodyMedium!,
      textAlign: TextAlign.right,
      child: Table(columnWidths: const {
        0: IntrinsicColumnWidth()
      }, children: [
        const TableRow(children: [
          TableCell(child: Text("")),
          TableCell(child: Text("Flights")),
          TableCell(child: Text("Distance")),
          TableCell(child: Text("Time"))
        ]),

        // --- Totals
        TableRow(children: [
          const TableCell(
              child: Padding(
            padding: EdgeInsets.only(right: 10),
            child: Text("Total"),
          )),
          TableCell(child: Text("${logs.length}", style: const TextStyle(color: Colors.blue))),
          TableCell(
              child: Text.rich(TextSpan(children: [richValue(UnitType.distCoarse, totalDist, digits: 8, decimals: 1)]),
                  style: const TextStyle(color: Colors.lightGreen))),
          TableCell(
              child: Text("${(totalDur.inMinutes / 60).toStringAsFixed(1)} hr",
                  style: const TextStyle(color: Colors.amber))),
        ]),

        // --- Averages
        TableRow(children: [
          const TableCell(
              child: Padding(
            padding: EdgeInsets.only(right: 10),
            child: Text("Average"),
          )),
          const TableCell(child: Text("")),
          TableCell(
              child: Text.rich(
                  TextSpan(children: [
                    richValue(UnitType.distCoarse, totalDist / max(1, logs.length), digits: 8, decimals: 1)
                  ]),
                  style: const TextStyle(color: Colors.lightGreen))),
          TableCell(
              child: Text(
            "${(totalDur.inHours / max(1, logs.length)).toStringAsFixed(1)} hr",
            style: const TextStyle(color: Colors.amber),
          )),
        ]),
      ]),
    );
  }
}
