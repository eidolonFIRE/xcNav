import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/util/waypoint.dart';

class FlightPlan with ChangeNotifier {
  List<Waypoint> waypoints = [
    // TODO: remove these "test waypoints"
    Waypoint("test1", [LatLng(37, -121)], false),
    Waypoint("test2", [LatLng(38, -121)], true),
    Waypoint("test3", [LatLng(37.5, -121), LatLng(36.5, -121)], true),
    Waypoint("test4", [LatLng(37, -122), LatLng(37.5, -121)], false),
  ];

  int? selectedIndex;
  Waypoint? get selectedWp =>
      (selectedIndex != null && selectedIndex! < waypoints.length)
          ? waypoints[selectedIndex!]
          : null;

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

  void toggleOptional(int index) {
    waypoints[index].isOptional = !waypoints[index].isOptional;
    notifyListeners();
  }

  void moveWaypoint(int index, LatLng newPoint) {
    // TODO: support polylines
    waypoints[index].latlng = [newPoint];
    notifyListeners();
  }

  void sortWaypoint(int oldIndex, int newIndex) {
    Waypoint temp = waypoints[oldIndex];
    waypoints.removeAt(oldIndex);
    if (newIndex > oldIndex) newIndex--;
    waypoints.insert(newIndex, temp);

    if (selectedIndex != null) {
      if (selectedIndex == oldIndex) {
        selectWaypoint(newIndex);
      } else if (newIndex <= selectedIndex! && oldIndex > selectedIndex!) {
        selectWaypoint(selectedIndex! + 1);
      } else if (selectedIndex! <= newIndex && selectedIndex! > oldIndex) {
        selectWaypoint(selectedIndex! - 1);
      }
    }

    // TODO: sockets message

    notifyListeners();
  }

  Polyline _buildTripSnakeSegment(List<LatLng> points) {
    return Polyline(
      points: points,
      color: Colors.black,
      strokeWidth: 3,
    );
  }

  List<Polyline> buildTripSnake() {
    List<Polyline> retval = [];

    List<LatLng> points = [];
    waypoints.forEach((wp) {
      // skip optional waypoints
      if (wp.isOptional) return;

      if (wp.latlng.length > 1) {
        points.add(wp.latlng[0]);
        // pinch off trip snake
        retval.add(_buildTripSnakeSegment(points));
        // start again at last point
        points = [wp.latlng[wp.latlng.length - 1]];
      } else {
        points.add(wp.latlng[0]);
      }
    });
    if (points.length > 1) retval.add(_buildTripSnakeSegment(points));
    return retval;
  }
}
