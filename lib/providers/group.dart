import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

// Models
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/models/geo.dart';

class Group with ChangeNotifier {
  String? _currentGroupID;
  Map<String, Pilot> pilots = {};
  SharedPreferences? prefs;

  // --- Get/Set current group_id
  String? get currentGroupID => _currentGroupID;

  set currentGroupID(String? newGroupID) {
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

  Future fetchAvatarS3(String pilotID) async {
    Uri uri = Uri.https("gx49w49rb4.execute-api.us-west-1.amazonaws.com",
        "/xcnav_avatar_service", {"pilot_id": pilotID});
    return http
        .get(
      uri,
    )
        .then((http.Response response) {
      final int statusCode = response.statusCode;

      if (statusCode < 200 || statusCode > 400) {
        throw Exception("Error while fetching avatar");
      }
      return json.decode(response.body);
    });
  }

  void processNewPilot(dynamic p) async {
    Pilot newPilot = Pilot(p["id"], p["name"], Geo());

    // Make fresh local pilot
    if (p["avatar_hash"] != null && p["avatar_hash"] != "") {
      // - Check if we have locally cached file matching pilot_id
      Directory tempDir = await getTemporaryDirectory();
      File fileAvatar = File("${tempDir.path}/avatars/${newPilot.id}.jpg");

      if (await fileAvatar.exists()) {
        // load cached file
        Uint8List loadedBytes = await fileAvatar.readAsBytes();
        String loadedHash = md5.convert(loadedBytes).toString();

        if (loadedHash == p["avatar_hash"]) {
          // cache hit
          debugPrint("Loaded avatar from cache");
          newPilot.avatar = Image.memory(loadedBytes);
          newPilot.avatarHash = loadedHash;
        }
      }

      if (newPilot.avatarHash == null) {
        // - cache miss, load from S3
        fetchAvatarS3(newPilot.id).then((value) {
          Uint8List bytes = base64Decode(value["avatar"]);
          newPilot.avatar = Image.memory(bytes);
          newPilot.avatarHash = md5.convert(bytes).toString();

          // save file to the temp file
          fileAvatar
              .create(recursive: true)
              .then((value) => fileAvatar.writeAsBytes(bytes));
        });
      }
    } else {
      // - fallback on default avatar
      newPilot.avatar = Image.asset("assets/images/default_avatar.png");
    }

    // Add / Replace local pilot instance
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
}
