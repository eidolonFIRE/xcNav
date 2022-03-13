import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

// Models
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

class Group with ChangeNotifier {
  String? _currentGroupID;
  Map<String, Pilot> pilots = {};
  SharedPreferences? prefs;

  // --- Get/Set current group_id
  String? get currentGroupID => _currentGroupID;
  set currentGroupID(String? newGroupID) {
    _currentGroupID = newGroupID;
    if (newGroupID != null) {
      debugPrint("Joined group: $newGroupID");
      saveGroup(newGroupID);
    } else {
      debugPrint("Left Group");
      pilots.clear();
    }
    notifyListeners();
  }

  bool hasPilot(String pilotID) => pilots.containsKey(pilotID);

  Group() {
    SharedPreferences.getInstance().then((value) => prefs = value);
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

  void processNewPilot(dynamic p) {
    Pilot newPilot = Pilot(p["id"], p["name"], Geo());

    // Make fresh local pilot
    if (p["avatar"] != null && p["avatar"] != "") {
      pilots[p["id"]] = newPilot;

      // - Check if we have locally cached file matching pilot_id
      // - if we don't, fetch from S3
      // - else, hash what we have and check it against the given hash
      // - if it doesn't match, fetch from s3

      // newPilot.avatar = Image.memory(imgBits);
      newPilot.avatarHash = "";
    } else {
      newPilot.avatar = Image.asset("assets/images/default_avatar.png");
    }

    // Add / Replace local pilot instance
    pilots[p] = newPilot;
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
      // TODO: check index and name match
      pilot.selectedWaypoint = index;
    }
  }
}
