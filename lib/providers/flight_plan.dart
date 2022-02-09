import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/util/waypoint.dart';






class FlightPlan with ChangeNotifier {
  List<Waypoint> waypoints = [
    // TODO: remove these "test waypoints"
    Waypoint("test1", [LatLng(37, 121)], false),
    Waypoint("test2", [LatLng(38, 121)], true),
    Waypoint("test3", [LatLng(36, 121), LatLng(36.5, 121)], true),
    Waypoint("test4", [LatLng(37, 122), LatLng(37.5, 121)], false),
  ];

  int? selectedIndex;
  Waypoint? get selectedWp => (selectedIndex != null && selectedIndex! < waypoints.length) ? waypoints[selectedIndex!] : null;

  void addWaypoint(Waypoint newPoint) {
    waypoints.add(newPoint);

    notifyListeners();
  }

  void selectWaypoint(int index) {
    selectedIndex = index;
    notifyListeners();
  }

  void addWaypointNew(String name, LatLng pos, bool? isOptional) {
    // TODO: insert in particular place
    waypoints.add(Waypoint(name, [pos], isOptional ?? false));
    notifyListeners();
  }


  void removeSelectedWaypoint() {
    if (selectedIndex != null) removeWaypoint(selectedIndex!);
  }


  void removeWaypoint(int index) {
    waypoints.removeAt(index);
    if (waypoints.isEmpty) {
      selectedIndex = null;
    }
    // TODO: officially update selected waypoint
    notifyListeners();
  }


  void sortWaypoint(int oldIndex, int newIndex) {
    Waypoint temp = waypoints[oldIndex];
    waypoints.removeAt(oldIndex);
    waypoints.insert(newIndex > oldIndex ? (newIndex - 1) : newIndex, temp);

    // TODO: sockets message

    notifyListeners();
  }


}
