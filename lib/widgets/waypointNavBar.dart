import 'package:feature_discovery/feature_discovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/map_marker.dart';

Widget buildWaypointNavBar(BuildContext context, VoidCallback showFlightPlan) {
  TextStyle instrLower = const TextStyle(fontSize: 35);
  TextStyle instrUpper = const TextStyle(fontSize: 40);
  TextStyle instrLabel = TextStyle(fontSize: 14, color: Colors.grey.shade400, fontStyle: FontStyle.italic);

  return Consumer2<ActivePlan, MyTelemetry>(builder: (context, activePlan, myTelemetry, child) {
    ETA etaNext = activePlan.selectedIndex != null
        ? activePlan.etaToWaypoint(myTelemetry.geo, myTelemetry.geo.spd, activePlan.selectedIndex!)
        : ETA(0, const Duration());

    final curWp = activePlan.selectedWp;

    return DescribedFeatureOverlay(
      featureId: "flightPlan",
      title: const Text("Flight Plan"),
      description: const Text("Swipe up to see flight plan."),
      tapTarget: const Icon(
        Icons.swipe_up,
        color: Colors.black,
        size: 40,
      ),
      child: Container(
        color: Theme.of(context).backgroundColor,
        child: SafeArea(
          minimum: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // --- Previous Waypoint
              IconButton(
                onPressed: () {
                  final wp = activePlan.isReversed ? activePlan.findNextWaypoint() : activePlan.findPrevWaypoint();
                  if (wp != null) activePlan.selectWaypoint(wp);
                },
                iconSize: 40,
                color: (activePlan.selectedIndex != null && activePlan.selectedIndex! > 0)
                    ? Colors.white
                    : Colors.grey.shade700,
                icon: SvgPicture.asset(
                  "assets/images/reverse_back.svg",
                  color:
                      ((activePlan.isReversed ? activePlan.findNextWaypoint() : activePlan.findPrevWaypoint()) != null)
                          ? Colors.white
                          : Colors.grey.shade700,
                ),
              ),

              // --- Next Waypoint Info
              Expanded(
                child: GestureDetector(
                  onPanDown: (details) {
                    // debugPrint("${MediaQuery.of(context).size.height - details.globalPosition.dy}");
                    // Limit the hitbox at the very bottom so it doesn't interfere with system bar
                    if (MediaQuery.of(context).size.height - details.globalPosition.dy > 30) {
                      showFlightPlan();
                    }
                  },
                  // onTap: showFlightPlan,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 60),
                    color: Theme.of(context).backgroundColor,
                    child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: (curWp != null)
                              ? [
                                  // --- Current Waypoint Label
                                  // RichText(
                                  Text.rich(
                                    TextSpan(children: [
                                      WidgetSpan(
                                        child: SizedBox(width: 20, height: 30, child: MapMarker(curWp, 30)),
                                      ),
                                      const TextSpan(text: "  "),
                                      TextSpan(
                                        text: curWp.name,
                                        style: const TextStyle(color: Colors.white, fontSize: 30),
                                      ),
                                    ]),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(
                                    width: MediaQuery.of(context).size.width / 2,
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
                                        richHrMin(
                                            duration: etaNext.time, valueStyle: instrLower, unitStyle: instrLabel),
                                    ]),
                                  ),
                                ]
                              : const [Text("Select Waypoint")],
                        )),
                  ),
                ),
              ),
              // --- Next Waypoint
              IconButton(
                  onPressed: () {
                    final wp = !activePlan.isReversed ? activePlan.findNextWaypoint() : activePlan.findPrevWaypoint();
                    if (wp != null) activePlan.selectWaypoint(wp);
                  },
                  iconSize: 40,
                  color: (activePlan.selectedIndex != null &&
                          (!activePlan.isReversed ? activePlan.findNextWaypoint() : activePlan.findPrevWaypoint()) !=
                              null)
                      ? Colors.white
                      : Colors.grey.shade700,
                  icon: const Icon(
                    Icons.arrow_forward,
                  )),
            ],
          ),
        ),
      ),
    );
  });
}
