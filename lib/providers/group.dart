import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Models
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/models/waypoint.dart';

class PastGroup {
  // [id] == name
  List<Pilot> pilots = [];
  late final String id;
  late final DateTime timestamp;

  PastGroup(this.id, this.timestamp, this.pilots);
  PastGroup.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    timestamp = DateTime.fromMillisecondsSinceEpoch(json["timestamp"]);
    for (Map<String, dynamic> each in json["pilots"]) {
      Pilot p = Pilot.fromJson(each);
      pilots.add(p);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "pilots": pilots.map((value) => value.toJson()).toList(),
      "timestamp": timestamp.millisecondsSinceEpoch,
    };
  }
}

class Group with ChangeNotifier {
  String? _currentGroupID;
  Map<String, Pilot> pilots = {};
  SharedPreferences? prefs;

  Map<String, PastGroup> pastGroups = {};

  // --- Get/Set current group_id
  String? get currentGroupID => _currentGroupID;

  set currentGroupID(String? newGroupID) {
    if (newGroupID != _currentGroupID) {
      // Remember this group
      if (_currentGroupID != null && pilots.isNotEmpty) {
        _appendToPastGroups();
      }

      // Join the new group
      _currentGroupID = newGroupID;
      pilots.clear();
      if (newGroupID != null) {
        debugPrint("Joined group: $newGroupID");
        saveGroup(newGroupID);
      } else {
        debugPrint("Left Group");
      }

      notifyListeners();
    }
  }

  Iterable<Pilot> get activePilots => pilots.values.where((each) =>
      each.geo != null &&
      each.geo!.time > (DateTime.now().subtract(const Duration(minutes: 2)).millisecondsSinceEpoch));

  void _appendToPastGroups() {
    PastGroup pg = PastGroup(_currentGroupID!, DateTime.now(), pilots.values.toList());
    debugPrint("Appended to past groups. (id: ${pg.id}, ${pg.pilots.length} pilots)");
    pastGroups[_currentGroupID!] = pg;
    _savePastGroups();
  }

  void _savePastGroups() {
    prefs?.setStringList("me.pastGroups", pastGroups.values.map((e) => jsonEncode(e.toJson())).toList());
    // debugPrint("Save pastGroups: ${pastGroups.values.map((e) => jsonEncode(e.toJson())).toList().join(", ")}");
  }

  bool hasPilot(String pilotID) => pilots.containsKey(pilotID);

  Group() {
    SharedPreferences.getInstance().then((value) {
      prefs = value;

      // Load past groups
      var pastGroupsRaw = prefs!.getStringList("me.pastGroups");
      if (pastGroupsRaw != null) {
        pastGroupsRaw
            // parse each object
            .map((e) => PastGroup.fromJson(jsonDecode(e)))
            // remove any groups too old
            .where((each) => each.timestamp.isAfter(DateTime.now().subtract(const Duration(hours: 72))))
            .forEach((g) {
          pastGroups[g.id] = g;
        });

        debugPrint("Loaded ${pastGroups.length} past groups.");
      }
    });
  }

  void saveGroup(String groupID) {
    if (prefs != null) {
      prefs!.setString("group.currentGroupID", groupID);
    }
  }

  String? loadGroup() {
    if (prefs != null) {
      return prefs!.getString("group.currentGroupID");
    }
    return null;
  }

  /// Add or Replace local pilot instance
  void processNewPilot(dynamic p) async {
    pilots[p["id"]] = Pilot.fromJson(p);
    _appendToPastGroups();
    notifyListeners();
  }

  void updatePilotTelemetry(String? pilotID, dynamic telemetry, int timestamp) {
    if (pilotID != null) {
      Pilot? pilot = pilots[pilotID];
      if (pilot != null) pilots[pilotID]!.updateTelemetry(telemetry, timestamp);
      notifyListeners();
    }
  }

  void removePilot(String? pilotID) {
    if (pilotID != null) {
      pilots.remove(pilotID);
      notifyListeners();
    }
  }

  void pilotSelectedWaypoint(String pilotID, WaypointID waypointID) {
    Pilot? pilot = pilots[pilotID];
    if (pilot != null) {
      pilot.selectedWp = waypointID;
    }
    notifyListeners();
  }
}
