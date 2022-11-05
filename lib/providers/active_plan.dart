import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

class ActivePlan with ChangeNotifier {
  final Map<WaypointID, Waypoint> waypoints = {};
  bool isSaved = false;

  void Function(
    WaypointAction action,
    Waypoint waypoint,
  )? onWaypointAction;

  void Function(WaypointID waypointID)? onSelectWaypoint;

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

  Waypoint? _selectedWp;
  Waypoint? get selectedWp => _selectedWp;
  set selectedWp(Waypoint? waypoint) {
    // check this waypoint is in our list
    if (waypoint != null && waypoints.containsKey(waypoint.id)) {
      _selectedWp = waypoint;
      if (onSelectWaypoint != null) onSelectWaypoint!(waypoint.id);
      notifyListeners();
    }
  }

  void load() async {
    debugPrint("Loading waypoints");
    final prefs = await SharedPreferences.getInstance();
    final List<String>? items = prefs.getStringList("flightPlan.waypoints");
    if (items != null) {
      for (String wpUnparsed in items) {
        final wp = Waypoint.fromJson(jsonDecode(wpUnparsed));
        waypoints[wp.id] = wp;
      }
    }
  }

  void save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("flightPlan.waypoints", waypoints.values.map((e) => e.toString()).toList());
  }

  void parseWaypointsSync(Map<String, dynamic> planData) {
    waypoints.clear();
    // add back each waypoint
    for (dynamic each in planData.values) {
      final wp = Waypoint.fromJson(each);
      waypoints[wp.id] = wp;
    }
    notifyListeners();
  }

  // Called from client
  void backendInsertWaypoint(Waypoint waypoint) {
    waypoints[waypoint.id] = waypoint;
    notifyListeners();
  }

  void backendRemoveWaypoint(WaypointID id) {
    if (id == selectedWp?.id) selectedWp = null;
    waypoints.remove(id);
    isSaved = false;
    notifyListeners();
  }

  void removeWaypoint(WaypointID waypointID) {
    if (selectedWp?.id == waypointID) {
      selectedWp = null;
    }
    backendRemoveWaypoint(waypointID);
    // callback
    if (onWaypointAction != null && waypoints.containsKey(waypointID)) {
      onWaypointAction!(WaypointAction.delete, waypoints[waypointID]!);
    }
  }

  void moveWaypoint(WaypointID id, List<LatLng> latlngs) {
    if (waypoints.containsKey(id)) {
      waypoints[id]?.latlng = latlngs;
      // callback
      if (onWaypointAction != null && waypoints.containsKey(id)) {
        onWaypointAction!(WaypointAction.update, waypoints[id]!);
      }
      isSaved = false;
      notifyListeners();
    }
  }

  void updateWaypoint(Waypoint waypoint) {
    waypoints[waypoint.id] = waypoint;

    // callback
    if (onWaypointAction != null) {
      onWaypointAction!(WaypointAction.update, waypoint);
    }

    isSaved = false;
    notifyListeners();
  }

  Polyline buildNextWpIndicator(Geo geo) {
    List<LatLng> points = [geo.latLng];

    if (selectedWp != null) {
      // update wp guide
      LatLng? target;
      if (selectedWp!.latlng.length > 1) {
        target = geo.nearestPointOnPath(selectedWp!.latlng, false).latlng;
      } else if (selectedWp!.latlng.isNotEmpty) {
        target = selectedWp!.latlng[0];
      }
      if (target != null) points.add(target);
    }

    return Polyline(points: points, color: Colors.red, strokeWidth: 5);
  }
}
