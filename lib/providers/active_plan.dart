import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/barb.dart';

import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

class ActivePlan with ChangeNotifier {
  final Map<WaypointID, Waypoint> waypoints = {};
  bool isSaved = false;

  void Function(
    WaypointAction action,
    Waypoint waypoint,
  )? onWaypointAction;

  void Function(WaypointID? waypointID)? onSelectWaypoint;

  /// Points when measument on the map is being made.
  List<LatLng>? mapMeasurement;

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

  WaypointID? _selectedWp;
  WaypointID? get selectedWp => _selectedWp;
  set selectedWp(WaypointID? waypointID) {
    // check this waypoint is in our list
    if (waypoints.containsKey(waypointID) || waypointID == null) {
      _selectedWp = waypointID;
      // Don't notify backend if it's ephemeral
      if (waypoints[waypointID]?.ephemeral == false) {
        onSelectWaypoint?.call(waypointID);
      } else {
        // (deselect from other's point of view)
        onSelectWaypoint?.call(null);
      }
      notifyListeners();
    }
  }

  Waypoint? getSelectedWp() {
    if (waypoints.containsKey(_selectedWp)) {
      return waypoints[_selectedWp];
    } else {
      return null;
    }
  }

  void load() async {
    debugPrint("Loading waypoints");
    final prefs = await SharedPreferences.getInstance();
    final List<String>? items = prefs.getStringList("flightPlan.waypoints");
    if (items != null) {
      for (String wpUnparsed in items) {
        final wp = Waypoint.fromJson(jsonDecode(wpUnparsed));
        if (wp.validate()) {
          waypoints[wp.id] = wp;
        }
      }
    }
  }

  void save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        "flightPlan.waypoints",
        waypoints.values
            .where((element) => (!element.ephemeral && element.validate()))
            .map((e) => e.toString())
            .toList());
  }

  void clearAllWayponits() {
    waypoints.clear();
    notifyListeners();
  }

  void parseWaypointsSync(Map<String, dynamic> planData) {
    // Attempt to preserve orientation of paths so selected
    // paths don't get flipped back each time server syncs.
    Map<String, bool> isReversed = {};
    for (final each in waypoints.values.where((e) => e.isPath)) {
      isReversed[each.id] = each.isReversed;
    }

    // Only remove waypoints that aren't emphemeral
    waypoints.removeWhere((key, value) => !value.ephemeral);
    // add back each waypoint
    for (dynamic each in planData.values) {
      final wp = Waypoint.fromJson(each);
      if (wp.validate()) {
        waypoints[wp.id] = wp;
        // Restore orientation
        if (isReversed.containsKey(wp.id)) {
          waypoints[wp.id]!.isReversed = isReversed[wp.id] ?? false;
        }
      }
    }
    notifyListeners();
  }

  // Called from client
  void backendInsertWaypoint(Waypoint waypoint) {
    waypoints[waypoint.id] = waypoint;
    notifyListeners();
  }

  void backendRemoveWaypoint(WaypointID id) {
    if (id == selectedWp) selectedWp = null;
    waypoints.remove(id);
    isSaved = false;
    notifyListeners();
  }

  void removeWaypoint(WaypointID waypointID) {
    // callback
    if (onWaypointAction != null && waypoints.containsKey(waypointID) && !waypoints[waypointID]!.ephemeral) {
      onWaypointAction!(WaypointAction.delete, waypoints[waypointID]!);
    }
    backendRemoveWaypoint(waypointID);
  }

  void moveWaypoint(WaypointID id, List<LatLng> latlngs) {
    if (waypoints.containsKey(id)) {
      waypoints[id]?.latlng = latlngs;
      // callback
      if (onWaypointAction != null && waypoints.containsKey(id) && !waypoints[id]!.ephemeral) {
        onWaypointAction!(WaypointAction.update, waypoints[id]!);
      }
      isSaved = false;
      notifyListeners();
    }
  }

  void updateWaypoint(Waypoint waypoint, {bool shouldCallback = true}) {
    waypoints[waypoint.id] = waypoint;

    // callback
    if (shouldCallback && onWaypointAction != null && !waypoint.ephemeral) {
      onWaypointAction!(WaypointAction.update, waypoint);
    }

    isSaved = false;
    notifyListeners();
  }

  /// Setting the `baseTiles` will change the style of the polylines to be best on that layer.
  List<Polyline> buildNextWpIndicator(Geo geo, double interval, {MapTileSrc? baseTiles}) {
    final waypointETA = getSelectedWp()?.eta(geo, 1);

    if (waypointETA != null) {
      final points = [geo.latlng] + getSelectedWp()!.latlngOriented.sublist(waypointETA.pathIntercept?.index ?? 0);
      switch (baseTiles) {
        case MapTileSrc.sectional:
          return [
            Polyline(points: points, color: const Color.fromARGB(180, 255, 0, 255), strokeWidth: 20),
            Polyline(points: points, color: Colors.black, strokeWidth: 4, isDotted: true),
          ];
        case MapTileSrc.satellite:
          return [
            Polyline(points: points, color: Colors.white70, strokeWidth: 20),
            Polyline(points: points, color: Colors.black, strokeWidth: 4, isDotted: true),
          ];
        default:
          return [
            Polyline(points: points, color: const Color.fromARGB(180, 255, 255, 0), strokeWidth: 20),
            Polyline(points: points, color: Colors.black, strokeWidth: 4, isDotted: true),
          ];
      }
    }

    return [];
  }

  List<Barb> buildNextWpBarbs(Geo geo, double interval) {
    final waypointETA = getSelectedWp()?.eta(geo, 1);
    List<Barb> barbs = [];

    /// I tried some algorithms to replace this, but turns out this is simpler and more performant. \shrug
    int barbSpacing(int t) {
      if (t < 5) {
        return 1;
      } else if (t < 10) {
        return 5;
      } else if (t < 50) {
        return 10;
      } else if (t < 100) {
        return 50;
      } else {
        return 100;
      }
    }

    // Dashes
    if (waypointETA != null) {
      for (int t = 1; t < waypointETA.distance / interval; t += barbSpacing(t)) {
        barbs.add(getSelectedWp()!
            .interpolate(t * interval, waypointETA.pathIntercept?.index ?? 0, initialLatlng: geo.latlng));
      }

      return barbs;
    }

    return [];
  }
}
