import 'dart:convert';
import 'dart:math';

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

  List<Polyline> buildNextWpIndicator(Geo geo, double interval) {
    if (selectedWp != null) {
      final waypointETA = selectedWp!.eta(geo, 1);

      // Underlying grey line
      List<Polyline> lines = [];
      lines.add(Polyline(
          points: [geo.latLng] + selectedWp!.latlng.sublist(waypointETA.pathIntercept?.index ?? 0),
          color: Colors.white60,
          strokeWidth: 20));

      // Dashes
      List<LatLng> points = [];
      for (double t = 1; t < waypointETA.distance; t += min(interval, waypointETA.distance - t)) {
        points.add(selectedWp!.interpolate(t, waypointETA.pathIntercept?.index ?? 0, initialLatlng: geo.latLng).latlng);
      }
      for (int t = 1; t < points.length - 1; t += 2) {
        lines.add(Polyline(
            points: [points[t], points[t + 1]],
            // Dark dash every 10th mile
            color: (t % 5 == 4) ? Colors.black : Colors.black45,
            strokeWidth: 20,
            strokeCap: StrokeCap.butt));
      }

      return lines;
    } else {
      return [];
    }
  }
}
