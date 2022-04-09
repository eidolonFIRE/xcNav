import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/models/eta.dart';

class ActivePlan with ChangeNotifier {
  List<Waypoint> waypoints = [];
  bool isReversed = false;

  void Function(
    WaypointAction action,
    int index,
    int? newIndex,
    Waypoint? data,
  )? onWaypointAction;

  void Function(int index)? onSelectWaypoint;

  @override
  ActivePlan() {
    load();
  }

  @override
  void dispose() {
    save();
    super.dispose();
  }

  @override
  void notifyListeners() {
    save();
    super.notifyListeners();
  }

  int? selectedIndex;
  Waypoint? get selectedWp =>
      (selectedIndex != null && selectedIndex! < waypoints.length)
          ? waypoints[selectedIndex!]
          : null;

  void load() async {
    debugPrint("Loading waypoints");
    final prefs = await SharedPreferences.getInstance();
    final List<String>? items = prefs.getStringList("flightPlan.waypoints");
    if (items != null) {
      for (String wpUnparsed in items) {
        Map wp = jsonDecode(wpUnparsed);
        List<dynamic> latlng = wp["latlng"];
        waypoints.add(Waypoint(
            wp["name"],
            latlng.map((e) => LatLng(e[0], e[1])).toList(),
            wp["isOptional"] ?? false,
            wp["icon"],
            wp["color"]));
        debugPrint("+ ${wp["name"]}");
      }
    }
  }

  void save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        "flightPlan.waypoints", waypoints.map((e) => e.toString()).toList());
  }

  void selectWaypoint(int index) {
    selectedIndex = index;
    // callback
    if (onSelectWaypoint != null) onSelectWaypoint!(index);
    notifyListeners();
  }

  void parseFlightPlanSync(List<dynamic> planData) {
    waypoints.clear();
    // add back each waypoint
    for (dynamic each in planData) {
      waypoints.add(Waypoint.fromJson(each));
    }
    notifyListeners();
  }

  int _resolveNewWaypointIndex(int? index) {
    if (index != null) {
      return max(0, min(waypoints.length, index));
    } else {
      if (selectedIndex != null) {
        // TODO: support reverse direction flight plan
        return selectedIndex! + 1;
      } else {
        return 0;
      }
    }
  }

  // Called from client
  void backendInsertWaypoint(int index, Waypoint newPoint) {
    waypoints.insert(_resolveNewWaypointIndex(index), newPoint);
    notifyListeners();
  }

  // Called from UI
  void insertWaypoint(int? index, String name, LatLng pos, bool? isOptional,
      String? icon, int? color) {
    Waypoint newWaypoint =
        Waypoint(name, [pos], isOptional ?? false, icon, color);
    int resolvedIndex = _resolveNewWaypointIndex(index);
    waypoints.insert(resolvedIndex, newWaypoint);

    // callback
    if (onWaypointAction != null) {
      onWaypointAction!(WaypointAction.add, resolvedIndex, null, newWaypoint);
    }
    notifyListeners();
  }

  void backendReplaceWaypoint(int index, Waypoint replacement) {
    waypoints[index] = replacement;
    notifyListeners();
  }

  void removeSelectedWaypoint() {
    if (selectedIndex != null) removeWaypoint(selectedIndex!);
  }

  void backendRemoveWaypoint(int index) {
    waypoints.removeAt(index);
    if (waypoints.isEmpty) {
      selectedIndex = null;
    }
    if (selectedIndex != null && selectedIndex! >= waypoints.length) {
      selectWaypoint(waypoints.length - 1);
    }
    notifyListeners();
  }

  void removeWaypoint(int index) {
    backendRemoveWaypoint(index);
    // callback
    if (onWaypointAction != null) {
      onWaypointAction!(WaypointAction.delete, index, null, null);
    }
  }

  void toggleOptional(int index) {
    waypoints[index].isOptional = !waypoints[index].isOptional;

    // callback
    if (onWaypointAction != null) {
      onWaypointAction!(WaypointAction.modify, index, null, waypoints[index]);
    }
    notifyListeners();
  }

  void moveWaypoint(int index, LatLng newPoint) {
    // TODO: support polylines
    waypoints[index].latlng = [newPoint];
    // callback
    if (onWaypointAction != null) {
      onWaypointAction!(WaypointAction.modify, index, null, waypoints[index]);
    }
    notifyListeners();
  }

  void editWaypoint(int? index, String name, String? icon, int? color) {
    if (index != null || selectedIndex != null) {
      int i = index ?? selectedIndex!;

      waypoints[i].name = name;
      waypoints[i].color = color;
      waypoints[i].icon = icon;

      // callback
      if (onWaypointAction != null) {
        onWaypointAction!(WaypointAction.modify, i, null, waypoints[i]);
      }
      notifyListeners();
    }
  }

  void backendSortWaypoint(int oldIndex, int newIndex) {
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
    notifyListeners();
  }

  void sortWaypoint(int oldIndex, int newIndex) {
    backendSortWaypoint(oldIndex, newIndex);
    // callback
    if (onWaypointAction != null) {
      onWaypointAction!(WaypointAction.sort, oldIndex, newIndex, null);
    }
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
    for (Waypoint wp in waypoints) {
      // skip optional waypoints
      if (wp.isOptional) continue;

      if (wp.latlng.length > 1) {
        points.add(wp.latlng[0]);
        // pinch off trip snake
        retval.add(_buildTripSnakeSegment(points));
        // start again at last point
        points = [wp.latlng[wp.latlng.length - 1]];
      } else {
        points.add(wp.latlng[0]);
      }
    }

    if (points.length > 1) retval.add(_buildTripSnakeSegment(points));
    return retval;
  }

  Polyline buildNextWpIndicator(Geo geo) {
    List<LatLng> points = [geo.latLng];

    if (selectedWp != null) {
      // update wp guide
      LatLng? target;
      if (selectedWp!.latlng.length > 1) {
        // TODO: support intercept to line
        // target = L.GeometryUtil.interpolateOnLine(_map, selectedWp, L.GeometryUtil.locateOnLine(_map, L.polyline(selectedWp), geoTolatlng(me.geoPos))).latLng;
      } else {
        target = selectedWp!.latlng[0];
      }
      if (target != null) points.add(target);
    }

    return Polyline(points: points, color: Colors.red, strokeWidth: 4);
  }

  // ETA from a location to a waypoint
  // If target is a path, result is dist to nearest tangent + remaining path
  ETA etaToWaypoint(LatLng latlng, double speed, int waypointIndex) {
    if (waypointIndex < waypoints.length && speed > 0) {
      Waypoint target = waypoints[waypointIndex];
      if (target.latlng.length > 1) {
        // TODO: support path

      } else {
        double dist = Geo.calc.distance(latlng, target.latlng[0]);
        return ETA.fromSpeed(dist, speed);
      }
    }
    return ETA(0, 0);
  }

  // // ETA from a waypoint to the end of the trip
  ETA etaToTripEnd(double speed, int waypointIndex) {
    // sum up the route
    double dist = 0;
    if (waypointIndex < waypoints.length && speed > 0) {
      int? prevIndex;
      for (int i = waypointIndex;
          isReversed ? (i >= 0) : (i < waypoints.length);
          i += isReversed ? -1 : 1) {
        // skip optional waypoints
        Waypoint wp_i = waypoints[i];
        if (wp_i.isOptional) continue;

        if (prevIndex != null) {
          // Will take the last point of the current waypoint, nearest point of the next
          LatLng prevLatlng = isReversed
              ? waypoints[prevIndex].latlng.last
              : waypoints[prevIndex].latlng.first;
          dist += latlngCalc.distance(
              isReversed ? wp_i.latlng.last : wp_i.latlng.first, prevLatlng);

          // add path distance
          if (wp_i.latlng.length > 1 && wp_i.length != null) {
            dist += wp_i.length!;
          }
        }
        prevIndex = i;
      }
      return ETA.fromSpeed(dist, speed);
    }
    return ETA(0, 0);
  }
}
