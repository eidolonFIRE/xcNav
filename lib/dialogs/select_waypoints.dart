import 'package:flutter/material.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/widgets/waypoint_card.dart';

Future<List<Waypoint>?> selectWaypoints(BuildContext context, List<Waypoint> waypoints) {
  return showDialog<List<Waypoint>>(
      context: context,
      builder: (context) {
        Set<int> checkedElements = {};
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
              contentPadding: const EdgeInsets.all(1),
              content: SizedBox(
                width: MediaQuery.of(context).size.width - 10,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: waypoints.length,
                  itemBuilder: (context, index) => WaypointCard(
                    index: index,
                    waypoint: waypoints[index],
                    onSelect: () {
                      setState(
                        () {
                          if (checkedElements.contains(index)) {
                            checkedElements.remove(index);
                          } else {
                            checkedElements.add(index);
                          }
                        },
                      );
                    },
                    onToggleOptional: () {},
                    isSelected: checkedElements.contains(index),
                    showPilots: false,
                  ),
                ),
              ),
              actions: [
                TextButton.icon(
                    label: const Text("Add Selected"),
                    onPressed: () {
                      // Return list of selected waypoints
                      Navigator.pop(context, checkedElements.map((e) => waypoints[e]).toList());
                    },
                    icon: const Icon(
                      Icons.check,
                      color: Colors.lightGreen,
                    ))
              ]);
        });
      });
}
