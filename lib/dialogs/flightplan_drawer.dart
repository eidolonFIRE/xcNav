import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:xcnav/dialogs/save_plan.dart';
import 'package:xcnav/dialogs/edit_latlng.dart';
import 'package:xcnav/models/waypoint.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/providers/wind.dart';

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
Widget flightPlanDrawer(Function setFocusMode, VoidCallback onNewPath, Function onEditPoints) {
  return Consumer2<ActivePlan, MyTelemetry>(builder: (context, activePlan, myTelemetry, child) {
    ETA etaNext = activePlan.selectedIndex != null
        ? activePlan.etaToWaypoint(myTelemetry.geo, myTelemetry.geo.spd, activePlan.selectedIndex!)
        : ETA(0, 0);
    ETA etaTrip = activePlan.etaToTripEnd(
        myTelemetry.geo.spd, activePlan.selectedIndex ?? 0, Provider.of<Wind>(context, listen: false));
    etaTrip += etaNext;

    if (activePlan.includeReturnTrip && !activePlan.isReversed) {
      // optionally include eta for return trip
      etaTrip += activePlan.etaToTripEnd(myTelemetry.geo.spd, 0, Provider.of<Wind>(context, listen: false));
    }

    int etaTripMin = min(999 * 60, (etaTrip.time / 60000).ceil());
    String etaTripValue = (etaTripMin >= 60) ? (etaTripMin / 60).toStringAsFixed(1) : etaTripMin.toString();
    String etaTripUnit = (etaTripMin >= 60) ? "hr" : "min";

    // Handle infinite ETA
    if (etaTrip.time < 0) {
      etaTripValue = "∞";
      etaTripUnit = "";
    }

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
                icon: const ImageIcon(AssetImage("assets/images/add_waypoint_pin.png"), color: Colors.lightGreen)),
            // --- Add New Path
            IconButton(
                iconSize: 25,
                onPressed: onNewPath,
                icon: const ImageIcon(AssetImage("assets/images/add_waypoint_path.png"), color: Colors.yellow)),
            // --- New from Lat Lng
            IconButton(
                iconSize: 25,
                onPressed: () {
                  editLatLng(context).then((value) {
                    if (value != null) {
                      editWaypoint(context, Waypoint("", [value], false, null, null), isNew: true, isPath: false)
                          ?.then((newWaypoint) {
                        if (newWaypoint != null) {
                          final plan = Provider.of<ActivePlan>(context, listen: false);
                          plan.insertWaypoint(plan.waypoints.length, newWaypoint.name, newWaypoint.latlng, false,
                              newWaypoint.icon, newWaypoint.color);
                        }
                      });
                    }
                  });
                },
                icon: const ImageIcon(AssetImage("assets/images/crosshair.png"))),
            // --- Save Plan
            IconButton(
                iconSize: 25,
                onPressed: () {
                  Navigator.pop(context);
                  savePlan(context);
                },
                icon: const Icon(Icons.save_as)),
          ],
        ),

        Divider(
          thickness: 2,
          height: 0,
          color: Theme.of(context).backgroundColor,
        ),

        // --- Waypoint list
        Expanded(
          child: ListView(primary: true, children: [
            // --- List of waypoints
            ReorderableListView.builder(
              shrinkWrap: true,
              primary: false,
              itemCount: activePlan.waypoints.length,
              itemBuilder: (context, i) => Slidable(
                key: ValueKey(activePlan.waypoints[i]),
                dragStartBehavior: DragStartBehavior.start,
                startActionPane: ActionPane(extentRatio: 0.15, motion: const ScrollMotion(), children: [
                  SlidableAction(
                    onPressed: (e) => {activePlan.removeWaypoint(i)},
                    icon: Icons.delete,
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ]),
                endActionPane: ActionPane(
                  extentRatio: 0.3,
                  motion: const ScrollMotion(),
                  children: [
                    SlidableAction(
                      onPressed: (e) {
                        editWaypoint(
                          context,
                          activePlan.waypoints[i],
                          editPointsCallback: () => onEditPoints(i),
                        )?.then((newWaypoint) {
                          if (newWaypoint != null) {
                            // --- Update selected waypoint
                            Provider.of<ActivePlan>(context, listen: false).updateWaypoint(
                                i, newWaypoint.name, newWaypoint.icon, newWaypoint.color, newWaypoint.latlng);
                          }
                        });
                      },
                      icon: Icons.edit,
                      backgroundColor: Colors.grey.shade400,
                      foregroundColor: Colors.black,
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: Container(
                        color: Colors.grey.shade400,
                        child: const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Icon(
                            Icons.drag_handle,
                            size: 24,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                child: WaypointCard(
                  waypoint: activePlan.waypoints[i],
                  index: i,
                  onSelect: () {
                    debugPrint("Selected $i");
                    activePlan.selectWaypoint(i);
                  },
                  onToggleOptional: () {
                    activePlan.toggleOptional(i);
                  },
                  isSelected: i == activePlan.selectedIndex,
                ),
              ),
              onReorder: (oldIndex, newIndex) {
                debugPrint("WP order: $oldIndex --> $newIndex");
                activePlan.sortWaypoint(oldIndex, newIndex);
                Provider.of<Group>(context, listen: false).fixPilotSelectionsOnSort(oldIndex, newIndex);
              },
            ),
            // This shows when flight plan is empty
            if (activePlan.waypoints.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  "Flightplan is Empty",
                  textAlign: TextAlign.center,
                  style: instrLabel,
                ),
              ),
            // --- Switch to include return trip
            if (activePlan.waypoints.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius:
                            const BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40))),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sync),
                          const Text(
                            " Include Return Trip",
                          ),
                          Switch(
                              activeColor: Colors.lightBlueAccent,
                              value: activePlan.includeReturnTrip,
                              onChanged: (value) => {activePlan.includeReturnTrip = value}),
                        ],
                      ),
                    ),
                  ),
                ),
              )
          ]),
        ),

        // --- Trip Options
        Divider(
          thickness: 2,
          height: 0,
          color: Theme.of(context).backgroundColor,
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    "Trip Remaining",
                    style: instrLabel,
                    // textAlign: TextAlign.left,
                  ),
                ),
                // --- Trip ETA
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: convertDistValueCoarse(
                                  Provider.of<Settings>(context, listen: false).displayUnitsDist, etaTrip.distance)
                              .toStringAsFixed(1),
                          style: instrLower),
                      TextSpan(
                          text: unitStrDistCoarse[Provider.of<Settings>(context, listen: false).displayUnitsDist],
                          style: instrLabel),
                      if (myTelemetry.inFlight)
                        TextSpan(
                          text: "   " + etaTripValue,
                          style: instrLower,
                        ),
                      if (myTelemetry.inFlight) TextSpan(text: etaTripUnit, style: instrLabel),
                      if (myTelemetry.inFlight && myTelemetry.fuel > 0 && myTelemetry.fuelTimeRemaining < etaNext.time)
                        const WidgetSpan(
                            child: Padding(
                          padding: EdgeInsets.only(left: 20),
                          child: FuelWarning(35),
                        )),
                    ]),
                  ),
                ),
              ],
            ),
            const Divider(
              height: 0,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Use Wind"),
                    Switch(
                      value: activePlan.useWind,
                      activeColor: Colors.lightBlueAccent,
                      onChanged: (value) => {activePlan.useWind = value},
                      activeThumbImage: Provider.of<Wind>(context).result != null
                          ? IconImageProvider(Icons.check, color: Colors.black)
                          : IconImageProvider(Icons.question_mark, color: Colors.black),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Returning",
                    ),
                    Switch(
                        value: activePlan.isReversed,
                        activeColor: Colors.lightBlueAccent,
                        activeThumbImage: IconImageProvider(Icons.arrow_upward, color: Colors.black),
                        inactiveThumbImage: IconImageProvider(Icons.arrow_downward, color: Colors.black),
                        onChanged: (value) => {activePlan.isReversed = value}),
                  ],
                ),
              ],
            )
          ],
        )
      ],
    );
  });
}
