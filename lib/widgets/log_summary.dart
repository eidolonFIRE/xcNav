import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';

class LogSummary extends StatelessWidget {
  LogSummary({
    super.key,
    required this.log,
  });

  final FlightLog log;
  final dateFormat = DateFormat("h:mm a");
  static const unitStyle = TextStyle(color: Colors.grey, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(fontSize: 16, height: 1.5),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Duration"),
            Text.rich(
                richHrMin(
                    duration: log.durationTime,
                    longUnits: true,
                    // valueStyle: Theme.of(context).textTheme.bodyMedium!,
                    unitStyle: unitStyle),
                textAlign: TextAlign.end)
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Distance"),
            Text.rich(
              richValue(UnitType.distCoarse, log.durationDist, decimals: 1, unitStyle: unitStyle),
              textAlign: TextAlign.end,
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Avg Speed"),
            Text.rich(
              richValue(UnitType.speed, log.meanSpd, decimals: 1, unitStyle: unitStyle),
              textAlign: TextAlign.end,
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Max Altitude"),
            Text.rich(
              richValue(UnitType.distFine, log.maxAlt, decimals: 1, unitStyle: unitStyle),
              textAlign: TextAlign.end,
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Best 1min Climb"),
            Text.rich(
              richValue(UnitType.vario, log.bestClimb, decimals: 1, unitStyle: unitStyle),
              textAlign: TextAlign.end,
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Total Elev Gain"),
            Text.rich(
              richValue(UnitType.distFine, log.altGained, decimals: 0, unitStyle: unitStyle),
              textAlign: TextAlign.end,
            ),
          ]),
        ],
      ),
    );
  }
}
