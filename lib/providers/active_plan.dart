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
  bool _useWind = false;
  bool isSaved = false;

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
      (selectedIndex != null && selectedIndex! < waypoints.length) ? waypoints[selectedIndex!] : null;

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

  bool get useWind => _useWind;
  set useWind(bool value) {
    _useWind = value;
    debugPrint("Used wind: $value");
    notifyListeners();
  }

  void load() async {
    debugPrint("Loading waypoints");
    final prefs = await SharedPreferences.getInstance();
    final List<String>? items = prefs.getStringList("flightPlan.waypoints");
    if (items != null) {
      for (String wpUnparsed in items) {
        Map wp = jsonDecode(wpUnparsed);
        waypoints.add(Waypoint.fromJson(wp));
      }
    }
  }

  void save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("flightPlan.waypoints", waypoints.map((e) => e.toString()).toList());
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
        return max(0, min(selectedIndex! + (isReversed ? -1 : 1), waypoints.length));
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
  void insertWaypoint(int? index, String name, List<LatLng> latlngs, bool? isOptional, String? icon, int? color) {
    Waypoint newWaypoint = Waypoint(name, latlngs.toList(), icon, color);
    int resolvedIndex = _resolveNewWaypointIndex(index);
    waypoints.insert(resolvedIndex, newWaypoint);

    // callback
    if (onWaypointAction != null) {
      onWaypointAction!(WaypointAction.add, resolvedIndex, null, newWaypoint);
    }
    isSaved = false;
    notifyListeners();
  }

  void backendReplaceWaypoint(int index, Waypoint replacement) {
    waypoints[index] = replacement;
    isSaved = false;
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
    isSaved = false;
    notifyListeners();
  }

  void removeWaypoint(int index) {
    backendRemoveWaypoint(index);
    // callback
    if (onWaypointAction != null) {
      onWaypointAction!(WaypointAction.delete, index, null, null);
    }
  }

  void moveWaypoint(int? index, List<LatLng> latlngs) {
    if (index != null || selectedIndex != null) {
      int i = index ?? selectedIndex!;
      waypoints[i].latlng = latlngs;
      // callback
      if (onWaypointAction != null) {
        onWaypointAction!(WaypointAction.modify, i, null, waypoints[i]);
      }
      isSaved = false;
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
      isSaved = false;
      notifyListeners();
    }
  }

  void updateWaypoint(int? index, String name, String? icon, int? color, List<LatLng> latlngs) {
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
      isSaved = false;
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
    isSaved = false;
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
}
