import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/endpoint.dart';

// --- Models
import 'package:xcnav/models/error_code.dart';
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

// --- Providers
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/util.dart';

enum ClientState {
  disconnected,
  connected,
  authenticated,
}

const double apiVersion = 7.0;

class MyHttpOverrides extends HttpOverrides {
  String goodCert;

  MyHttpOverrides(this.goodCert);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        return cert.pem == goodCert;
      };
  }
}

class Client with ChangeNotifier {
  WebSocket? socket;
  ClientState _state = ClientState.disconnected;

  int telemetrySkips = 0;
  int reconnectionWait = 0;

  final BuildContext globalContext;

  Client(this.globalContext) {
    debugPrint("Build Client");
    connect();
  }

  void sendToAWS(String action, dynamic payload) {
    debugPrint("TX: ${jsonEncode({"action": action, "body": payload})}");
    if (socket != null) {
      socket!.add(jsonEncode({"action": action, "body": payload}));
    }
  }

  ClientState get state => _state;
  set state(ClientState newState) {
    _state = newState;
    if (newState == ClientState.disconnected) {
      debugPrint("Reconnecting in ${reconnectionWait}sec...");
      if (socket != null) {
        socket!.close().then((value) {
          Timer(Duration(seconds: reconnectionWait), (() => connect()));
        });
      } else {
        Timer(Duration(seconds: reconnectionWait), (() => connect()));
      }
    }
    notifyListeners();
  }

  void connect() async {
    reconnectionWait += 1;

    if (serverEndpoint == null) {
      debugPrint("Waiting for server to be selected.");
      state = ClientState.disconnected;
    } else {
      HttpOverrides.global = MyHttpOverrides(serverEndpoint!.cert);
      WebSocket.connect(serverEndpoint!.apiUrl, headers: {"authorizationToken": serverEndpoint!.token})
          .then((newSocket) {
        reconnectionWait = 0;

        socket = newSocket;
        state = ClientState.connected;
        debugPrint("Connected!");

        socket!.listen(handleResponse, onError: (errorRaw) {
          debugPrint("RX-error: $errorRaw");
          state = ClientState.disconnected;
        }, onDone: () {
          debugPrint("RX-done");
          state = ClientState.disconnected;
        });

        Profile profile = Provider.of<Profile>(globalContext, listen: false);
        if (Profile.nameValidator(profile.name) == null) {
          authenticate(profile);
        }

        // Watch updates to Profile
        Provider.of<Profile>(globalContext, listen: false).addListener(() {
          Profile profile = Provider.of<Profile>(globalContext, listen: false);
          if (state == ClientState.connected) {
            authenticate(profile);
          } else if (state == ClientState.authenticated && profile.name != null) {
            // Just need to update server with new profile
            pushProfile(profile);
          }
        });

        // Register Callbacks to waypoints
        Provider.of<ActivePlan>(globalContext, listen: false).onWaypointAction = waypointsUpdate;
        Provider.of<ActivePlan>(globalContext, listen: false).onSelectWaypoint = selectWaypoint;
      }).onError((error, stackTrace) {
        debugPrint("Failed to connect! $error");
        state = ClientState.disconnected;
      });
    }
  }

  void handleResponse(dynamic response) {
    if (response == null || response == "") {
      debugPrint("Got a blank message!");
      return;
    }
    final jsonMsg = json.decode(response);
    debugPrint("RX: $jsonMsg");

    if (jsonMsg["body"] != null) {
      Map<String, dynamic> payload = jsonMsg["body"];

      switch (jsonMsg["action"]) {
        case "authResponse":
          handleAuthResponse(payload);
          break;
        case "updateProfileResponse":
          handleUpdateProfileResponse(payload);
          break;
        case "groupInfoResponse":
          handleGroupInfoResponse(payload);
          break;
        case "joinGroupResponse":
          handleJoinGroupResponse(payload);
          break;
        case "chatMessage":
          handleChatMessage(payload);
          break;
        case "pilotTelemetry":
          handlePilotTelemetry(payload);
          break;
        case "pilotJoinedGroup":
          handlePilotJoinedGroup(payload);
          break;
        case "pilotLeftGroup":
          handlePilotLeftGroup(payload);
          break;
        case "waypointsSync":
          handleWaypointsSync(payload);
          break;
        case "waypointsUpdate":
          handleWaypointsUpdate(payload);
          break;
        case "pilotSelectedWaypoint":
          handlePilotSelectedWaypoint(payload);
          break;
        default:
          debugPrint("RX-unknown action: ${jsonMsg["action"]}");
      }
    } else {
      debugPrint("There was some error! $response");
    }
  }

  // ############################################################################
  //
  //     Requests
  //
  // ############################################################################

  void authenticate(Profile profile) {
    if (state != ClientState.authenticated) {
      debugPrint("Authenticating) ${profile.name}, ${profile.id}");
      sendToAWS("authRequest", {
        "pilot": {
          "id": profile.id,
          "name": profile.name,
          "avatarHash": profile.avatarHash,
          "secretToken": profile.secretID,
        },
        "group_id": Provider.of<Group>(globalContext, listen: false).loadGroup(),
        "apiVersion": apiVersion,
      });
    } else {
      debugPrint("... we are already authenticated.");
    }
  }

  void pushProfile(Profile profile) {
    debugPrint("Push Profile: ${profile.name}, ${profile.id}");
    sendToAWS("updateProfile", {
      "pilot": {
        "id": profile.id,
        "name": profile.name,
        "avatarHash": profile.avatarHash,
        "secretToken": profile.secretID
      },
    });
  }

  void sendchatMessage(String text, {bool? isEmergency}) {
    Group group = Provider.of<Group>(globalContext, listen: false);
    sendToAWS("chatMessage", {
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "group_id": group.currentGroupID, // target group
      "pilot_id": "", // sender (filled in by backend)
      "text": text,
      "emergency": isEmergency ?? false,
    });
  }

  // --- send our telemetry
  void sendTelemetry(Geo geo) {
    if (state == ClientState.authenticated) {
      sendToAWS("pilotTelemetry", {
        "timestamp": geo.time,
        "pilot_id": "", // backend will fill this in
        "telemetry": {
          "gps": {
            "lat": geo.lat,
            "lng": geo.lng,
            "alt": geo.alt,
          },
        },
      });
    }
  }

  void requestGroupInfo(String? reqGroupID) {
    if (reqGroupID != null && reqGroupID != "") {
      sendToAWS("groupInfoRequest", {"group_id": reqGroupID});
    }
  }

  void _joinGroup(String reqGroupID) {
    sendToAWS("joinGroupRequest", {
      "group_id": reqGroupID.toLowerCase(),
    });
    debugPrint("Requesting Join Group $reqGroupID");
  }

  void joinGroup(BuildContext context, String reqGroupID) {
    // Autosave waypoints into library before they are replaced.
    final activePlan = Provider.of<ActivePlan>(context, listen: false);
    if (activePlan.waypoints.isNotEmpty && !activePlan.isSaved) {
      FlightPlan newPlan = FlightPlan("~Autosave: previous group");
      debugPrint("Autosaving waypoints to ${newPlan.name}");
      for (final each in activePlan.waypoints.values) {
        newPlan.waypoints[each.id] = Waypoint.from(each);
      }
      Provider.of<Plans>(context, listen: false).setPlan(newPlan);
      activePlan.isSaved = true;
    }
    _joinGroup(reqGroupID);
  }

  void waypointsUpdate(
    WaypointAction action,
    Waypoint waypoint,
  ) {
    sendToAWS("waypointsUpdate", {
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "hash": hashWaypointsData(Provider.of<ActivePlan>(globalContext, listen: false).waypoints),
      "action": action.index,
      "waypoint": waypoint.toJson(),
    });
  }

  void pushWaypoints() {
    sendToAWS("waypointsSync", {
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "waypoints": Map.fromEntries(Provider.of<ActivePlan>(globalContext, listen: false)
          .waypoints
          .values
          .where((element) => !element.ephemeral)
          .map((e) => MapEntry(e.id, e.toJson())))
    });
  }

  void selectWaypoint(WaypointID? waypointID) {
    sendToAWS("pilotSelectedWaypoint",
        {"pilot_id": Provider.of<Profile>(globalContext, listen: false).id, "waypoint_id": waypointID});
  }

  // ############################################################################
  //
  //     Response from Server
  //
  // ############################################################################

  // --- new text message from server
  void handleChatMessage(Map<String, dynamic> msg) {
    final group = Provider.of<Group>(globalContext, listen: false);
    String? currentGroupID = group.currentGroupID;
    final groupId = parseAsString(msg["group_id"]);
    if (groupId == currentGroupID) {
      Provider.of<ChatMessages>(globalContext, listen: false)
          .processMessageFromServer(group.pilots[parseAsString(msg["pilot_id"])]?.name ?? "", msg);
    } else {
      // getting messages from the wrong group!
      debugPrint("Wrong group ID! $currentGroupID, $groupId");
    }
  }

  //--- receive location of other pilots
  void handlePilotTelemetry(Map<String, dynamic> msg) {
    // if we know this pilot, update their telemetry
    Group group = Provider.of<Group>(globalContext, listen: false);
    final pilotId = parseAsString(msg["pilot_id"]);
    if (pilotId != null && group.hasPilot(pilotId)) {
      group.updatePilotTelemetry(pilotId, msg["telemetry"], msg["timestamp"]);
    } else {
      debugPrint("Unrecognized local pilot $pilotId");
      requestGroupInfo(group.currentGroupID);
    }
  }

  // --- new Pilot to group
  void handlePilotJoinedGroup(Map<String, dynamic> msg) {
    Map<String, dynamic> pilot = msg["pilot"];
    final pilotId = parseAsString(pilot["id"]);
    if (pilotId != null && pilotId != Provider.of<Profile>(globalContext, listen: false).id) {
      // update pilots with new info
      Group group = Provider.of<Group>(globalContext, listen: false);
      group.processNewPilot(pilotId, pilot);
    }
  }

  // --- Pilot left group
  void handlePilotLeftGroup(Map<String, dynamic> msg) {
    final pilotId = parseAsString(msg["pilot_id"]);
    if (pilotId == Provider.of<Profile>(globalContext, listen: false).id) {
      // ignore if it's us
      return;
    }
    Group group = Provider.of<Group>(globalContext, listen: false);
    group.removePilot(pilotId);
  }

  // --- Full waypoints sync
  void handleWaypointsSync(Map<String, dynamic> msg) {
    ActivePlan plan = Provider.of<ActivePlan>(globalContext, listen: false);
    plan.parseWaypointsSync(msg["waypoints"]);
  }

  // --- Process an update to group waypoints
  void handleWaypointsUpdate(Map<String, dynamic> msg) {
    // update the plan
    if (msg["action"] == WaypointAction.delete.index) {
      // Delete a waypoint
      final waypointId = parseAsString(msg["waypoint"]["id"]);
      if (waypointId != null) Provider.of<ActivePlan>(globalContext, listen: false).backendRemoveWaypoint(waypointId);
    } else if (msg["action"] == WaypointAction.update.index) {
      // Make updates to a waypoint
      if (msg["waypoint"] != null) {
        Provider.of<ActivePlan>(globalContext, listen: false)
            .updateWaypoint(Waypoint.fromJson(msg["waypoint"]), shouldCallback: false);
      }
    } else {
      // no-op
      return;
    }

    String hash = hashWaypointsData(Provider.of<ActivePlan>(globalContext, listen: false).waypoints);
    if (hash != msg["hash"]) {
      // DE-SYNC ERROR
      // restore backup
      debugPrint("Group Waypoints Desync!  $hash  ${msg['hash']}");

      // we are out of sync!
      requestGroupInfo(Provider.of<Group>(globalContext, listen: false).currentGroupID);
    }
  }

  // --- Process Pilot Waypoint selections
  void handlePilotSelectedWaypoint(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(globalContext, listen: false);
    final pilotId = parseAsString(msg["pilot_id"]);
    final waypointId = parseAsString(msg["waypoint_id"]);

    debugPrint("$pilotId selected wp: $waypointId");
    if (pilotId != null) {
      if (group.hasPilot(pilotId)) {
        group.pilotSelectedWaypoint(pilotId, waypointId);
      } else {
        // we don't have this pilot?
        requestGroupInfo(group.currentGroupID);
      }
    }
  }

  void handleAuthResponse(Map<String, dynamic> msg) {
    if (msg["status"] != ErrorCode.success.index) {
      state = ClientState.connected;
      debugPrint("Error Authenticating: ${msg["status"]}");
    } else {
      debugPrint("Authenticated!");
      state = ClientState.authenticated;

      // compare API version
      if (msg["apiVersion"] > apiVersion) {
        debugPrint("---/!\\--- Client is out of date!");
      } else if (msg["apiVersion"] < apiVersion) {
        debugPrint("---/!\\--- Server is out of date!");
      }

      Profile profile = Provider.of<Profile>(globalContext, listen: false);
      final pilotId = parseAsString(msg["pilot_id"]);
      if (pilotId != null) {
        profile.updateID(pilotId, msg["secretToken"]);

        // join the provided group
        Group group = Provider.of<Group>(globalContext, listen: false);
        group.currentGroupID = parseAsString(msg["group_id"]);
        requestGroupInfo(group.currentGroupID);

        // update profile
        if (msg["pilotMetaHash"] != profile.hash) {
          debugPrint("Server had outdate profile meta. (${msg["pilotMetaHash"]} != ${profile.hash})");
          pushProfile(profile);
        }
      } else {
        debugPrint("Error: failed to parse pilot_id");
      }
    }
  }

  void handleUpdateProfileResponse(Map<String, dynamic> msg) {
    if (msg["status"] != ErrorCode.success.index) {
      debugPrint("Error Updating profile ${msg['status']}");
    }
  }

  void handleGroupInfoResponse(Map<String, dynamic> msg) {
    if (msg["status"] != ErrorCode.success.index) {
      debugPrint("Error getting group info ${msg['status']}");
    } else {
      // ignore if it's not a group I'm in
      Group group = Provider.of<Group>(globalContext, listen: false);
      if (msg["group_id"] != group.currentGroupID) {
        debugPrint("Received info for another group.");
        return;
      }

      // update pilots with new info
      msg["pilots"].forEach((jsonPilot) {
        final pilotId = parseAsString(jsonPilot["id"]);
        if (pilotId != null && pilotId != Provider.of<Profile>(globalContext, listen: false).id) {
          group.processNewPilot(pilotId, jsonPilot);
        }
      });

      // refresh waypoints
      ActivePlan plan = Provider.of<ActivePlan>(globalContext, listen: false);
      if (msg["waypoints"] != null && msg["waypoints"].isNotEmpty) {
        plan.parseWaypointsSync(msg["waypoints"]);
      } else if (plan.waypoints.isNotEmpty) {
        // Push our waypoints
        debugPrint("Pushing our plan!");
        pushWaypoints();
      }
    }
  }

  void handleJoinGroupResponse(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(globalContext, listen: false);
    final groupId = parseAsString(msg["group_id"]);
    if (msg["status"] != ErrorCode.success.index) {
      // not a valid group
      if (msg["status"] == ErrorCode.invalidId.index) {
        debugPrint("Attempted to join invalid group $groupId");
      } else if (msg["status"] == ErrorCode.noop.index && groupId == group.currentGroupID) {
        // we were already in this group... update anyway
        group.currentGroupID = groupId;
      } else {
        debugPrint("Error joining group ${msg['status']}");
      }
    } else {
      // successfully joined group
      group.currentGroupID = groupId;
      requestGroupInfo(group.currentGroupID);
      // NOTE: This helps iOS devices show up immediately. They don't
      //       send location updates while the device isn't moving.
      final myTelemetry = Provider.of<MyTelemetry>(globalContext, listen: false);
      if (myTelemetry.geo != null) sendTelemetry(myTelemetry.geo!);
    }
  }
}
