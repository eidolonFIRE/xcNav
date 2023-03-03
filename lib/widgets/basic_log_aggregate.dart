import 'package:flutter/material.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';

class BasicLogAggregate extends StatelessWidget {
  const BasicLogAggregate({Key? key, required this.logs}) : super(key: key);

  final Iterable<FlightLog> logs;

  @override
  Widget build(BuildContext context) {
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
              child: Text.rich(
                  TextSpan(children: [
                    richValue(UnitType.distCoarse, logs.map((e) => e.durationDist).reduce((a, b) => a + b),
                        digits: 8, decimals: 1)
                  ]),
                  style: const TextStyle(color: Colors.lightGreen))),
          TableCell(
              child: Text("${logs.map((e) => e.durationTime).reduce((a, b) => a + b).inHours} hr",
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
                    richValue(
                        UnitType.distCoarse, logs.map((e) => e.durationDist).reduce((a, b) => a + b) / logs.length,
                        digits: 8, decimals: 1)
                  ]),
                  style: const TextStyle(color: Colors.lightGreen))),
          TableCell(
              child: Text(
            "${(logs.map((e) => e.durationTime).reduce((a, b) => a + b).inHours / logs.length).toStringAsFixed(1)} hr",
            style: const TextStyle(color: Colors.amber),
          )),
        ]),
      ]),
    );
  }
}
