import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Models
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/models/geo.dart';

class PastGroup {
  // [id] == name
  List<Pilot> pilots = [];
  late final String id;
  late final DateTime timestamp;

  PastGroup.new(this.id, this.timestamp, this.pilots);
  PastGroup.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    timestamp = DateTime.fromMillisecondsSinceEpoch(json["timestamp"]);
    for (Map<String, dynamic> each in json["pilots"]) {
      Pilot _p = Pilot.fromJson(each);
      pilots.add(_p);
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

  List<PastGroup> pastGroups = [];

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

      _cleanPastGroups();

      notifyListeners();
    }
  }

  void _appendToPastGroups() {
    PastGroup pg =
        PastGroup(_currentGroupID!, DateTime.now(), pilots.values.toList());
    debugPrint(
        "Appended to past groups. (id: ${pg.id}, ${pg.pilots.length} pilots)");
    pastGroups.add(pg);
  }

  /// Remove the current groupID from history
  void _cleanPastGroups() {
    pastGroups =
        pastGroups.where((element) => element.id != _currentGroupID).toList();
    _savePastGroups();
  }

  void _savePastGroups() {
    prefs?.setStringList("me.pastGroups",
        pastGroups.map((e) => jsonEncode(e.toJson())).toList());
    debugPrint(
        "Save pastGroups: ${pastGroups.map((e) => jsonEncode(e.toJson())).toList().join(", ")}");
  }

  bool hasPilot(String pilotID) => pilots.containsKey(pilotID);

  Group() {
    SharedPreferences.getInstance().then((value) {
      prefs = value;

      // Load past groups
      var _pastGroupsRaw = prefs!.getStringList("me.pastGroups");
      if (_pastGroupsRaw != null) {
        pastGroups = _pastGroupsRaw
            .map((e) => PastGroup.fromJson(jsonDecode(e)))
            .toList();

        debugPrint("Loaded ${pastGroups.length} past groups.");

        // remove any groups too old
        pastGroups = pastGroups
            .where((each) => each.timestamp
                .isAfter(DateTime.now().subtract(const Duration(hours: 24))))
            .toList();
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
    Pilot newPilot =
        Pilot(p["id"], p["name"] ?? "Anonymous", p["avatar_hash"], Geo());
    pilots[p["id"]] = newPilot;
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

  void pilotSelectedWaypoint(String pilotID, int index) {
    Pilot? pilot = pilots[pilotID];
    if (pilot != null) {
      pilot.selectedWaypoint = index;
    }
    notifyListeners();
  }

  void fixPilotSelectionsOnSort(int oldIndex, int newIndex) {
    for (final _p in pilots.values) {
      if (_p.selectedWaypoint != null) {
        if (_p.selectedWaypoint == oldIndex) {
          _p.selectedWaypoint = newIndex;
        } else if (newIndex <= _p.selectedWaypoint! &&
            oldIndex > _p.selectedWaypoint!) {
          _p.selectedWaypoint = _p.selectedWaypoint! + 1;
        } else if (_p.selectedWaypoint! <= newIndex &&
            _p.selectedWaypoint! > oldIndex) {
          _p.selectedWaypoint = _p.selectedWaypoint! - 1;
        }
      }
    }
  }
}
