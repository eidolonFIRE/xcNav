import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/providers/wind.dart';

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
    await prefs.setStringList(
        "flightPlan.waypoints", waypoints.map((e) => e.toString()).toList());
  }

  void selectWaypoint(int index) {
    selectedIndex = index;
    // callback
    if (onSelectWaypoint != null) onSelectWaypoint!(index);
    notifyListeners();
  }

  int? findNextWaypoint() {
    if (selectedIndex != null && selectedIndex! < waypoints.length - 1) {
      // (Skip optional waypoints)
      for (int i = selectedIndex! + 1; i < waypoints.length; i++) {
        if (!waypoints[i].isOptional) {
          return i;
        }
      }
    }
    return null;
  }

  int? findPrevWaypoint() {
    if (selectedIndex != null && selectedIndex! > 0) {
      // (Skip optional waypoints)
      for (int i = selectedIndex! - 1; i >= 0; i--) {
        if (!waypoints[i].isOptional) {
          return i;
        }
      }
    }
    return null;
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

  void toggleOptional(int index) {
    waypoints[index].isOptional = !waypoints[index].isOptional;

    // callback
    if (onWaypointAction != null) {
      onWaypointAction!(WaypointAction.modify, index, null, waypoints[index]);
    }
    isSaved = false;
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
    return ETA(0, const Duration());
  }

  /// ETA from a waypoint to the end of the trip
  ETA etaToTripEnd(double speed, int waypointIndex, Wind wind) {
    // sum up the route
    var retval = ETA(0, const Duration());
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
          final prevLatlng = isReversed
              ? waypoints[prevIndex].latlng.first
              : waypoints[prevIndex].latlng.last;
          final nextLatlng =
              isReversed ? wpIndex.latlng.first : wpIndex.latlng.last;

          if (wind.result != null && useWind) {
            if (wind.result!.windSpd >= wind.result!.airspeed) {
              // NO SOLUTION!
              debugPrint("No solution!");
              retval += ETA(
                  latlngCalc.distance(nextLatlng, prevLatlng) + wpIndex.length,
                  null);
            } else {
              /// This works by first canceling lateral speed loss by rotating our vector to compensate.
              /// Then, account for forward loss of speed.

              double relativeHdg = wind.result!.windHdg -
                  latlngCalc.bearing(prevLatlng, nextLatlng) * pi / 180 +
                  (isReversed ? 0 : pi);

              // debugPrint("Relative headings: ${relativeHdg % (2 * pi)}");

              retval += ETA.fromSpeed(
                  latlngCalc.distance(nextLatlng, prevLatlng),
                  Wind.remainingHeadway(relativeHdg, wind.result!.airspeed,
                      wind.result!.windSpd));
            }
          } else {
            // use your current speed
            retval += ETA.fromSpeed(
                latlngCalc.distance(nextLatlng, prevLatlng), speed);
          }
        }

        // Account for path lenths
        if (wpIndex.length > 0 && i != waypointIndex) {
          if (wind.result != null && useWind) {
            double relativeHdg = wind.result!.windHdg -
                latlngCalc.bearing(wpIndex.latlng.first, wpIndex.latlng.last) *
                    pi /
                    180 +
                (isReversed ? 0 : pi);

            retval += ETA.fromSpeed(
                wpIndex.length,
                Wind.remainingHeadway(
                    relativeHdg, wind.result!.airspeed, wind.result!.windSpd));
          } else {
            retval += ETA.fromSpeed(wpIndex.length, speed);
          }
        }

        prevIndex = i;
      }
      return retval;
    }
    return ETA(0, const Duration());
  }
}
