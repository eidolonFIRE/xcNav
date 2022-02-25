import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';

// Models
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

class Group with ChangeNotifier {
  String? _currentGroupID;
  Map<String, Pilot> pilots = {};

  // --- Get/Set current group_id
  String? get currentGroupID => _currentGroupID;
  set currentGroupID(String? newGroupID) {
    _currentGroupID = newGroupID;
    debugPrint("Joined group: $newGroupID");
    notifyListeners();
  }

  bool hasPilot(String pilotID) => pilots.containsKey(pilotID);

  void processNewPilot(dynamic p) {
    Pilot newPilot = Pilot(p["id"], p["name"], Geo());
    Uint8List imgBits = base64Decode(p["avatar"]);
    newPilot.avatar = Image.memory(imgBits);
    pilots[p["id"]] = newPilot;
    notifyListeners();
  }

  void updatePilotTelemetry(
      String? pilotID, dynamic telemetry, double timestamp) {
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

  void pilotSelectedWaypoint(String pilotID, dynamic wp) {
    Pilot? pilot = pilots[pilotID];
    if (pilot != null) {
      // TODO: check index and name match
      pilot.selectedWaypoint = wp["index"];
    }
  }
}
