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

  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final showFuelStats = log.sumFuelStat != null;
    return DefaultTextStyle(
      style: const TextStyle(fontSize: 16, height: 1.5),
      child: Scrollbar(
        thumbVisibility: true,
        trackVisibility: true,
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: ListView(shrinkWrap: true, controller: scrollController, children: [
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
            const Divider(
              height: 10,
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Max Altitude"),
              Text.rich(
                richValue(UnitType.distFine, log.maxAlt, decimals: 1, unitStyle: unitStyle),
                textAlign: TextAlign.end,
              ),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Best 30sec Climb"),
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
            const Divider(
              height: 10,
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Max G-Force"),
              Text(
                printDouble(value: log.maxG(), digits: 2, decimals: 2),
                textAlign: TextAlign.end,
              ),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Duration > 2G"),
              Text.rich(
                richMinSec(duration: log.durationOver2G, unitStyle: unitStyle),
                textAlign: TextAlign.end,
              ),
            ]),

            // --- Fuel Stats
            if (showFuelStats)
              Divider(
                height: 10,
              ),
            if (showFuelStats)
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Fuel Burn Rate"),
                Text.rich(TextSpan(children: [
                  TextSpan(text: printValue(UnitType.fuel, log.sumFuelStat?.rate ?? 0, decimals: 1) ?? "?"),
                  TextSpan(text: fuelRateStr, style: unitStyle)
                ])),
              ]),
            if (showFuelStats)
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Fuel Efficiency"),
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: printValue(
                              UnitType.distCoarse, (log.sumFuelStat?.mpl ?? 0) / unitConverters[UnitType.fuel]!(1),
                              decimals: 1) ??
                          "?"),
                  TextSpan(text: fuelEffStr, style: unitStyle)
                ]))
              ]),
          ]),
        ),
      ),
    );
  }
}
