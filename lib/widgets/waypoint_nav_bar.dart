import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

class WaypointNavBar extends StatelessWidget {
  final ActivePlan activePlan;
  const WaypointNavBar({Key? key, required this.activePlan}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    TextStyle instrLower = const TextStyle(fontSize: 30, color: Colors.black);
    TextStyle instrLabel = const TextStyle(fontSize: 14, color: Colors.black87);

    return Consumer<MyTelemetry>(builder: (context, myTelemetry, child) {
      late ETA etaNext;
      if (myTelemetry.geo != null) {
        etaNext =
            activePlan.getSelectedWp()?.eta(myTelemetry.geo!, myTelemetry.geo!.spdSmooth) ?? ETA(0, const Duration());
      } else {
        etaNext = ETA(0, const Duration());
      }

      final curWp = activePlan.getSelectedWp();

      return (curWp == null)
          ? Container()
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- Current Waypoint Label
                  // RichText(
                  Text.rich(
                    TextSpan(children: [
                      WidgetSpan(
                        child: getWpIcon(curWp.icon, 30, curWp.getColor()),
                      ),
                      const TextSpan(text: "  "),
                      TextSpan(
                        text: curWp.name,
                        style: instrLower,
                      ),
                    ]),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // --- Separator
                  SizedBox(
                    width: MediaQuery.of(context).size.width / 3,
                    child: Divider(
                      thickness: 1,
                      height: 8,
                      color: Colors.grey.shade700,
                    ),
                  ),

                  // --- ETA next
                  Text.rich(
                    TextSpan(children: [
                      richValue(UnitType.distCoarse, etaNext.distance,
                          digits: 4, decimals: 1, valueStyle: instrLower, unitStyle: instrLabel),
                      if (myTelemetry.inFlight) TextSpan(text: "   ", style: instrLower),
                      if (myTelemetry.inFlight)
                        richHrMin(duration: etaNext.time, valueStyle: instrLower, unitStyle: instrLabel),
                    ]),
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ));
    });
  }
}
