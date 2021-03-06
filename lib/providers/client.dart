import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:xcnav/dialogs/save_plan.dart';

// --- Models
import 'package:xcnav/models/error_code.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

// --- Providers
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/settings.dart';

enum ClientState {
  disconnected,
  connected,
  authenticated,
}

const double apiVersion = 5.2;

class Client with ChangeNotifier {
  WebSocket? socket;
  ClientState _state = ClientState.disconnected;

  final BuildContext context;

  Client(this.context) {
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
      debugPrint("Reconnecting!");
      if (socket != null) {
        socket!.close().then((value) {
          Timer(const Duration(seconds: 10), (() => connect()));
        });
      } else {
        connect();
      }
    }
    notifyListeners();
  }

  void connect() async {
    WebSocket.connect("wss://cilme82sm3.execute-api.us-west-1.amazonaws.com/production").then((newSocket) {
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

      Profile profile = Provider.of<Profile>(context, listen: false);
      authenticate(profile);

      // Watch updates to Profile
      Provider.of<Profile>(context, listen: false).addListener(() {
        Profile profile = Provider.of<Profile>(context, listen: false);
        if (state == ClientState.connected) {
          authenticate(profile);
        } else if (state == ClientState.authenticated && profile.name != null) {
          // Just need to update server with new profile
          pushProfile(profile);
        }
      });

      // Register Callbacks to flightPlan
      Provider.of<ActivePlan>(context, listen: false).onWaypointAction = flightPlanUpdate;
      Provider.of<ActivePlan>(context, listen: false).onSelectWaypoint = selectWaypoint;
    }).onError((error, stackTrace) {
      debugPrint("Failed to connect! $error");
      state = ClientState.disconnected;
    });
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
        case "flightPlanSync":
          handleFlightPlanSync(payload);
          break;
        case "flightPlanUpdate":
          handleflightPlanUpdate(payload);
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
      final settings = Provider.of<Settings>(context, listen: false);
      debugPrint("Authenticating) ${profile.name}, ${profile.id}");
      sendToAWS("authRequest", {
        "secret_id": profile.secretID,
        "pilot": {"id": profile.id, "name": profile.name, "avatar_hash": profile.avatarHash},
        "group": Provider.of<Group>(context, listen: false).loadGroup(),
        "tier_hash": crypto.sha256.convert((settings.patreonEmail + settings.patreonName).codeUnits).toString(),
      });
    } else {
      debugPrint("... we are already authenticated.");
    }
  }

  void pushProfile(Profile profile) {
    debugPrint("Push Profile: ${profile.name}, ${profile.id}");
    sendToAWS("updateProfile", {
      "pilot": {"id": profile.id, "name": profile.name, "avatar_hash": profile.avatarHash},
      "secret_id": profile.secretID
    });
  }

  void sendchatMessage(String text, {bool? isEmergency}) {
    Group group = Provider.of<Group>(context, listen: false);
    sendToAWS("chatMessage", {
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "group": group.currentGroupID, // target group
      "pilot_id": "", // sender (filled in by backend)
      "text": text,
      "emergency": isEmergency ?? false,
    });
  }

  // --- send our telemetry
  void sendTelemetry(Geo geo, double fuel) {
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
          "fuel": fuel,
        },
      });
    }
  }

  void requestGroupInfo(String? reqGroupID) {
    if (reqGroupID != null && reqGroupID != "") {
      sendToAWS("groupInfoRequest", {"group": reqGroupID});
    }
  }

  void _joinGroup(String reqGroupID) {
    sendToAWS("joinGroupRequest", {
      "group": reqGroupID.toLowerCase(),
    });
    debugPrint("Requesting Join Group $reqGroupID");
  }

  void joinGroup(BuildContext context, String reqGroupID) {
    savePlan(context, isSavingFirst: true).then((value) => _joinGroup(reqGroupID));
  }

  void leaveGroup(bool promptSplit) {
    // This is just alias to joining an unknown group
    Provider.of<Group>(context, listen: false).currentGroupID = null;
    Provider.of<ChatMessages>(context, listen: false).leftGroup();
    sendToAWS("joinGroupRequest", {"prompt_split": promptSplit});
  }

  void flightPlanUpdate(
    WaypointAction action,
    int index,
    int? newIndex,
    Waypoint? data,
  ) {
    sendToAWS("flightPlanUpdate", {
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "hash": hashFlightPlanData(Provider.of<ActivePlan>(context, listen: false).waypoints),
      "index": index,
      "action": action.index,
      "data": data?.toJson(),
      "new_index": newIndex,
    });
  }

  void pushFlightPlan() {
    sendToAWS("flightPlanSync", {
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "flight_plan": Provider.of<ActivePlan>(context, listen: false).waypoints.map((e) => e.toJson()).toList()
    });
  }

  void selectWaypoint(int index) {
    sendToAWS("pilotSelectedWaypoint", {"pilot_id": Provider.of<Profile>(context, listen: false).id, "index": index});
  }

  // ############################################################################
  //
  //     Response from Server
  //
  // ############################################################################

  // --- new text message from server
  void handleChatMessage(Map<String, dynamic> msg) {
    final group = Provider.of<Group>(context, listen: false);
    String? currentGroupID = group.currentGroupID;
    if (msg["group"] == currentGroupID) {
      Provider.of<ChatMessages>(context, listen: false).processMessageFromServer(group.pilots[msg["pilot_id"]]?.name ?? "", msg);
    } else {
      // getting messages from the wrong group!
      debugPrint("Wrong group ID! $currentGroupID, ${msg["group"]}");
    }
  }

  //--- receive location of other pilots
  void handlePilotTelemetry(Map<String, dynamic> msg) {
    // if we know this pilot, update their telemetry
    Group group = Provider.of<Group>(context, listen: false);
    if (group.hasPilot(msg["pilot_id"])) {
      group.updatePilotTelemetry(msg["pilot_id"], msg["telemetry"], msg["timestamp"]);
    } else {
      debugPrint("Unrecognized local pilot ${msg["pilot_id"]}");
      requestGroupInfo(group.currentGroupID);
    }
  }

  // --- new Pilot to group
  void handlePilotJoinedGroup(Map<String, dynamic> msg) {
    Map<String, dynamic> pilot = msg["pilot"];
    if (pilot["id"] != Provider.of<Profile>(context, listen: false).id) {
      // update pilots with new info
      Group group = Provider.of<Group>(context, listen: false);
      group.processNewPilot(pilot);
    }
  }

  // --- Pilot left group
  void handlePilotLeftGroup(Map<String, dynamic> msg) {
    if (msg["pilot_id"] == Provider.of<Profile>(context, listen: false).id) {
      // ignore if it's us
      return;
    }
    Group group = Provider.of<Group>(context, listen: false);
    group.removePilot(msg["pilot_id"]);
    if (msg["new_group"] != "") {
      // TODO: prompt yes/no should we follow them to new group
    }
  }

  // --- Full flight plan sync
  void handleFlightPlanSync(Map<String, dynamic> msg) {
    ActivePlan plan = Provider.of<ActivePlan>(context, listen: false);
    plan.parseFlightPlanSync(msg["flight_plan"]);
  }

  // --- Process an update to group flight plan
  void handleflightPlanUpdate(Map<String, dynamic> msg) {
    // make backup copy of the plan

    // update the plan
    if (msg["action"] == WaypointAction.delete.index) {
      // Delete a waypoint
      Provider.of<ActivePlan>(context, listen: false).backendRemoveWaypoint(msg["index"]);
    } else if (msg["action"] == WaypointAction.add.index) {
      // insert a new waypoint
      Provider.of<ActivePlan>(context, listen: false)
          .backendInsertWaypoint(msg["index"], Waypoint.fromJson(msg["data"]));
    } else if (msg["action"] == WaypointAction.sort.index) {
      // Reorder a waypoint
      Provider.of<ActivePlan>(context, listen: false).backendSortWaypoint(msg["index"], msg["new_index"]);
    } else if (msg["action"] == WaypointAction.modify.index) {
      // Make updates to a waypoint
      if (msg["data"] != null) {
        Provider.of<ActivePlan>(context, listen: false)
            .backendReplaceWaypoint(msg["index"], Waypoint.fromJson(msg["data"]));
      }
    } else {
      // no-op
      return;
    }

    String hash = hashFlightPlanData(Provider.of<ActivePlan>(context, listen: false).waypoints);
    if (hash != msg["hash"]) {
      // DE-SYNC ERROR
      // restore backup
      debugPrint("Group Flightplan Desync!  $hash  ${msg['hash']}");

      // we are out of sync!
      requestGroupInfo(Provider.of<Group>(context, listen: false).currentGroupID);
    }
  }

  // --- Process Pilot Waypoint selections
  void handlePilotSelectedWaypoint(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(context, listen: false);

    debugPrint("${msg["pilot_id"]} selected wp: ${msg["index"]}");
    if (group.hasPilot(msg["pilot_id"])) {
      group.pilotSelectedWaypoint(msg["pilot_id"], msg["index"]);
    } else {
      // we don't have this pilot?
      requestGroupInfo(group.currentGroupID);
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
      // TODO: should have big warning banners for this
      if (msg["api_version"] > apiVersion) {
        debugPrint("---/!\\--- Client is out of date!");
      } else if (msg["api_version"] < apiVersion) {
        debugPrint("---/!\\--- Server is out of date!");
      }

      Profile profile = Provider.of<Profile>(context, listen: false);
      profile.tier = msg["tier"];
      profile.updateID(msg["pilot_id"], msg["secret_id"]);

      // join the provided group
      Group group = Provider.of<Group>(context, listen: false);
      group.currentGroupID = msg["group"];
      requestGroupInfo(group.currentGroupID);

      // update profile
      if (msg["pilot_meta_hash"] != profile.hash) {
        debugPrint("Server had outdate profile meta. (${msg["pilot_meta_hash"]} != ${profile.hash})");
        pushProfile(profile);
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
      Group group = Provider.of<Group>(context, listen: false);
      if (msg["group"] != group.currentGroupID) {
        debugPrint("Received info for another group.");
        return;
      }

      // update pilots with new info
      msg["pilots"].forEach((jsonPilot) {
        if (jsonPilot["id"] != Provider.of<Profile>(context, listen: false).id) {
          group.processNewPilot(jsonPilot);
        }
      });

      // Clear out waypoints
      ActivePlan plan = Provider.of<ActivePlan>(context, listen: false);
      if (msg["flight_plan"] != null && msg["flight_plan"].isNotEmpty) {
        plan.parseFlightPlanSync(msg["flight_plan"]);
      } else if (plan.waypoints.isNotEmpty) {
        // Push our flightplan
        debugPrint("Pushing our plan!");
        pushFlightPlan();
      }
    }
  }

  void handleJoinGroupResponse(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(context, listen: false);
    if (msg["status"] != ErrorCode.success.index) {
      // not a valid group
      if (msg["status"] == ErrorCode.invalidId.index) {
        debugPrint("Attempted to join invalid group ${msg["group"]}");
      } else if (msg["status"] == ErrorCode.noop.index && msg["group"] == group.currentGroupID) {
        // we were already in this group... update anyway
        group.currentGroupID = msg["group"];
      } else {
        debugPrint("Error joining group ${msg['status']}");
      }
    } else {
      // successfully joined group
      group.currentGroupID = msg["group"];
      requestGroupInfo(group.currentGroupID);
    }
  }
}
