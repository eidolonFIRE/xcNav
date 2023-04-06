import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';

class LogSummary extends StatelessWidget {
  LogSummary({
    Key? key,
    required this.log,
  }) : super(key: key);

  final FlightLog log;
  final dateFormat = DateFormat("h:mm a");
  static const unitStyle = TextStyle(color: Colors.grey, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(fontSize: 18, height: 1.5),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        children: [
          TableRow(children: [
            const TableCell(child: Text("Duration")),
            TableCell(
                child: Text.rich(
                    richHrMin(
                        duration: log.durationTime,
                        longUnits: true,
                        // valueStyle: Theme.of(context).textTheme.bodyMedium!,
                        unitStyle: unitStyle),
                    textAlign: TextAlign.end))
          ]),
          TableRow(children: [
            const TableCell(child: Text("Distance")),
            TableCell(
                child: Text.rich(
              richValue(UnitType.distCoarse, log.durationDist, decimals: 1, unitStyle: unitStyle),
              textAlign: TextAlign.end,
            )),
          ]),
          TableRow(children: [
            const TableCell(child: Text("Avg Speed")),
            TableCell(
                child: Text.rich(
              richValue(UnitType.speed, log.meanSpd, decimals: 1, unitStyle: unitStyle),
              textAlign: TextAlign.end,
            )),
          ]),
          TableRow(children: [
            const TableCell(child: Text("Max Altitude")),
            TableCell(
                child: Text.rich(
              richValue(UnitType.distFine, log.maxAlt, decimals: 1, unitStyle: unitStyle),
              textAlign: TextAlign.end,
            )),
          ]),
          TableRow(children: [
            const TableCell(child: Text("Best 1min Climb")),
            TableCell(
                child: Text.rich(
              richValue(UnitType.vario, log.bestClimb, decimals: 1, unitStyle: unitStyle),
              textAlign: TextAlign.end,
            )),
          ]),
          TableRow(children: [
            const TableCell(child: Text("Total Elev Gain")),
            TableCell(
                child: Text.rich(
              richValue(UnitType.distFine, log.altGained, decimals: 0, unitStyle: unitStyle),
              textAlign: TextAlign.end,
            )),
          ]),
          // const TableRow(children: [TableCell(child: Text("")), TableCell(child: Text(""))]),
        ],
      ),
    );
  }
}
