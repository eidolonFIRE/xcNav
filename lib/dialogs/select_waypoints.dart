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
              // insetPadding: const EdgeInsets.only(left: 10, right: 10, top: 80, bottom: 80),
              contentPadding: EdgeInsets.all(1),
              // title: const Padding(
              //   padding: EdgeInsets.only(bottom: 20),
              //   child: Text("Select Waypoints"),
              // ),
              content: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height / 2),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: waypoints.length,
                  itemBuilder: (context, index) => ListTile(
                      // tileColor: Colors.grey.shade900,
                      minVerticalPadding: 0,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      // dense: true,
                      // visualDensity: VisualDensity.compact,
                      leading: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Checkbox(
                          onChanged: (checked) {
                            setState(
                              () {
                                if (checked ?? false) {
                                  checkedElements.add(index);
                                } else {
                                  checkedElements.remove(index);
                                }
                              },
                            );
                          },
                          value: checkedElements.contains(index),
                        ),
                      ),
                      title: WaypointCard(
                        index: index,
                        waypoint: waypoints[index],
                        onSelect: () {},
                        onToggleOptional: () {},
                        isSelected: false,
                        isFaded: false,
                        showPilots: false,
                      )),
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
