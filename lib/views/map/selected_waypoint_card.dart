import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/widgets/waypoint_nav_bar.dart';

/// Nav info for the selected waypoint, along the bottom of the map.
class SelectedWaypointCard extends StatelessWidget {
  const SelectedWaypointCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ActivePlan>(
      builder: (context, activePlan, _) {
        final curWaypoint = activePlan.getSelectedWp();
        if (curWaypoint != null) {
          return Padding(
            padding: const EdgeInsets.only(left: 60, right: 60, bottom: 10),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Stack(
                children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                          child: Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 150),
                              color: Colors.white38,
                              child: WaypointNavBar(activePlan: activePlan)))),
                  Positioned(
                      top: -40,
                      right: -40,
                      child: InkWell(
                        onTap: (() {
                          activePlan.selectedWp = null;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Icon(
                            Icons.cancel,
                            color: const Color.fromARGB(255, 255, 100, 100).withAlpha(200),
                            size: 20,
                          ),
                        ),
                      ))
                ],
              ),
            ),
          );
        } else {
          return Container();
        }
      },
    );
  }
}
