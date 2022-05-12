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
  bool _isReversed = false;
  bool _includeReturnTrip = false;

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

  bool get includeReturnTrip => _includeReturnTrip;
  set includeReturnTrip(bool value) {
    _includeReturnTrip = value;
    notifyListeners();
  }

  bool get isReversed => _isReversed;
  set isReversed(bool value) {
    _isReversed = value;
    notifyListeners();
  }

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
        return max(
            0, min(selectedIndex! + (isReversed ? -1 : 1), waypoints.length));
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
  void insertWaypoint(int? index, String name, List<LatLng> latlngs,
      bool? isOptional, String? icon, int? color) {
    Waypoint newWaypoint =
        Waypoint(name, latlngs.toList(), isOptional ?? false, icon, color);
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

  void moveWaypoint(int? index, List<LatLng> latlngs) {
    if (index != null || selectedIndex != null) {
      int i = index ?? selectedIndex!;
      waypoints[i].latlng = latlngs;
      // callback
      if (onWaypointAction != null) {
        onWaypointAction!(WaypointAction.modify, i, null, waypoints[i]);
      }
      notifyListeners();
    }
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

  void updateWaypoint(
      int? index, String name, String? icon, int? color, List<LatLng> latlngs) {
    if (index != null || selectedIndex != null) {
      int i = index ?? selectedIndex!;

      waypoints[i].name = name;
      waypoints[i].color = color;
      waypoints[i].icon = icon;
      waypoints[i].latlng = latlngs;

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
    if (newIndex > oldIndex) newIndex--;
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

      if (wp.latlng.isNotEmpty) {
        points.add(wp.latlng[0]);
      }
      if (wp.latlng.length > 1) {
        // pinch off trip snake
        retval.add(_buildTripSnakeSegment(points));
        // start again at last point
        points = [wp.latlng[wp.latlng.length - 1]];
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
        target = geo.nearestPointOnPath(selectedWp!.latlng, isReversed).latlng;
      } else if (selectedWp!.latlng.isNotEmpty) {
        target = selectedWp!.latlng[0];
      }
      if (target != null) points.add(target);
    }

    return Polyline(points: points, color: Colors.red, strokeWidth: 5);
  }

  /// ETA from a location to a waypoint
  /// If target is a path, result is dist to nearest intercept + remaining path
  ETA etaToWaypoint(Geo geo, double speed, int waypointIndex) {
    if (waypointIndex < waypoints.length) {
      Waypoint target = waypoints[waypointIndex];
      if (target.latlng.length > 1) {
        // --- to path
        final intercept = geo.nearestPointOnPath(target.latlng, isReversed);
        double dist = geo.distanceToLatlng(intercept.latlng) +
            target.lengthBetweenIndexs(
                intercept.index, isReversed ? 0 : target.latlng.length - 1);
        return ETA.fromSpeed(dist, speed);
      } else {
        // --- to point
        if (target.latlng.isNotEmpty) {
          double dist = geo.distanceToLatlng(target.latlng[0]);
          return ETA.fromSpeed(dist, speed);
        } else {
          return ETA.fromSpeed(0, speed);
        }
      }
    }
    return ETA(0, 0);
  }

  /// ETA from a waypoint to the end of the trip
  ETA etaToTripEnd(double speed, int waypointIndex) {
    // sum up the route
    double dist = 0;
    if (waypointIndex < waypoints.length) {
      int? prevIndex;
      for (int i = waypointIndex;
          isReversed ? (i >= 0) : (i < waypoints.length);
          i += isReversed ? -1 : 1) {
        // skip optional waypoints
        Waypoint wpIndex = waypoints[i];
        if (wpIndex.isOptional) continue;

        if (prevIndex != null &&
            wpIndex.latlng.isNotEmpty &&
            waypoints[prevIndex].latlng.isNotEmpty) {
          // Will take the last point of the current waypoint, first point of the next
          LatLng prevLatlng = isReversed
              ? waypoints[prevIndex].latlng.last
              : waypoints[prevIndex].latlng.first;
          dist += latlngCalc.distance(
              isReversed ? wpIndex.latlng.last : wpIndex.latlng.first,
              prevLatlng);

          // add path distance
          dist += wpIndex.length;
        }
        prevIndex = i;
      }
      return ETA.fromSpeed(dist, speed);
    }
    return ETA(0, 0);
  }
}
