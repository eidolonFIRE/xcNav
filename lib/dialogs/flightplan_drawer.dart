import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/settings.dart';

// --- Widgets
import 'package:xcnav/widgets/fuel_warning.dart';
import 'package:xcnav/widgets/icon_image.dart';
import 'package:xcnav/widgets/waypoint_card.dart';

// --- Misc
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/screens/home.dart';

/// Flightplan Menu
Widget flightPlanDrawer(Function setFocusMode, VoidCallback onNewPath,
    VoidCallback onEditWaypoint) {
  return Consumer2<ActivePlan, MyTelemetry>(
      builder: (context, activePlan, myTelemetry, child) {
    ETA etaNext = activePlan.selectedIndex != null
        ? activePlan.etaToWaypoint(
            myTelemetry.geo, myTelemetry.geo.spd, activePlan.selectedIndex!)
        : ETA(0, 0);
    ETA etaTrip = activePlan.etaToTripEnd(
        myTelemetry.geo.spd, activePlan.selectedIndex ?? 0);
    etaTrip += etaNext;

    if (activePlan.includeReturnTrip && !activePlan.isReversed) {
      // optionally include eta for return trip
      etaTrip += activePlan.etaToTripEnd(myTelemetry.geo.spd, 0);
    }

    int etaTripMin = (etaTrip.time / 60000).ceil();
    String etaTripValue = (etaTripMin >= 60)
        ? (etaTripMin / 60).toStringAsFixed(1)
        : etaTripMin.toString();
    String etaTripUnit = (etaTripMin >= 60) ? "hr" : "min";

    return Column(
      children: [
        // Waypoint menu buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // --- Add New Waypoint
            IconButton(
                iconSize: 25,
                onPressed: () {
                  Navigator.pop(context);
                  setFocusMode(FocusMode.addWaypoint);
                },
                icon: const ImageIcon(
                    AssetImage("assets/images/add_waypoint_pin.png"),
                    color: Colors.lightGreen)),
            // --- Add New Path
            IconButton(
                iconSize: 25,
                onPressed: onNewPath,
                icon: const ImageIcon(
                    AssetImage("assets/images/add_waypoint_path.png"),
                    color: Colors.yellow)),
            // --- Edit Waypoint
            IconButton(
              iconSize: 25,
              onPressed: () => editWaypoint(
                context,
                false,
                activePlan.selectedWp?.latlng ?? [],
                editPointsCallback: onEditWaypoint,
              ),
              icon: const Icon(Icons.edit),
            ),
            // --- Delete Selected Waypoint
            IconButton(
                iconSize: 25,
                onPressed: () => activePlan.removeSelectedWaypoint(),
                icon: const Icon(Icons.delete, color: Colors.red)),
          ],
        ),

        Divider(
          thickness: 2,
          height: 0,
          color: Colors.grey[900],
        ),

        // --- Waypoint list
        Expanded(
          child: ListView(primary: true, children: [
            ReorderableListView.builder(
              shrinkWrap: true,
              primary: false,
              itemCount: activePlan.waypoints.length,
              itemBuilder: (context, i) => WaypointCard(
                key: ValueKey(activePlan.waypoints[i]),
                waypoint: activePlan.waypoints[i],
                index: i,
                isFaded: activePlan.selectedIndex != null &&
                    ((activePlan.isReversed && i > activePlan.selectedIndex!) ||
                        (!activePlan.isReversed &&
                            i < activePlan.selectedIndex!)),
                onSelect: () {
                  debugPrint("Selected $i");
                  activePlan.selectWaypoint(i);
                },
                onToggleOptional: () {
                  activePlan.toggleOptional(i);
                },
                isSelected: i == activePlan.selectedIndex,
              ),
              onReorder: (oldIndex, newIndex) {
                debugPrint("WP order: $oldIndex --> $newIndex");
                activePlan.sortWaypoint(oldIndex, newIndex);
              },
            ),
            if (activePlan.waypoints.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  "Flightplan is Empty",
                  textAlign: TextAlign.center,
                  style: instrLabel,
                ),
              ),
            if (activePlan.waypoints.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.sync),
                    const Text(
                      " Include Return Trip",
                    ),
                    Switch(
                        value: activePlan.includeReturnTrip,
                        onChanged: (value) =>
                            {activePlan.includeReturnTrip = value}),
                  ],
                ),
              )
          ]),
        ),

        // --- Trip Options
        Divider(
          thickness: 2,
          height: 0,
          color: Colors.grey[900],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    "Trip Remaining",
                    style: instrLabel,
                    // textAlign: TextAlign.left,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Returning",
                    ),
                    Switch(
                        value: activePlan.isReversed,
                        activeThumbImage: IconImageProvider(Icons.arrow_upward,
                            color: Colors.black),
                        inactiveThumbImage: IconImageProvider(
                            Icons.arrow_downward,
                            color: Colors.black),
                        onChanged: (value) => {activePlan.isReversed = value}),
                  ],
                ),
              ],
            ),
            // --- Trip ETA
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: convertDistValueCoarse(
                              Provider.of<Settings>(context, listen: false)
                                  .displayUnitsDist,
                              etaTrip.distance)
                          .toStringAsFixed(1),
                      style: instrLower),
                  TextSpan(
                      text: unitStrDistCoarse[
                          Provider.of<Settings>(context, listen: false)
                              .displayUnitsDist],
                      style: instrLabel),
                  if (myTelemetry.inFlight)
                    TextSpan(
                      text: "   " + etaTripValue,
                      style: instrLower,
                    ),
                  if (myTelemetry.inFlight)
                    TextSpan(text: etaTripUnit, style: instrLabel),
                  if (myTelemetry.inFlight &&
                      myTelemetry.fuel > 0 &&
                      myTelemetry.fuelTimeRemaining < etaNext.time)
                    const WidgetSpan(
                        child: Padding(
                      padding: EdgeInsets.only(left: 20),
                      child: FuelWarning(35),
                    )),
                ]),
              ),
            ),
          ],
        )
      ],
    );
  });
}
