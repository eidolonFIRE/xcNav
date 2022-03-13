import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// --- Models
import 'package:xcnav/models/error_code.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

// --- Providers
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/flight_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/chat.dart';

enum WaypointAction {
  none,
  add,
  modify,
  delete,
  sort,
}

enum ClientState {
  disconnected,
  connected,
  authenticated,
}

const double apiVersion = 5.0;

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
      if (socket != null) {
        debugPrint("Reconnecting!");
        socket!.close().then((value) => connect());
      }
    }
    notifyListeners();
  }

  void connect() async {
    WebSocket.connect(
            "wss://cilme82sm3.execute-api.us-west-1.amazonaws.com/production")
        .then((newSocket) {
      socket = newSocket;
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

      // Subscribe to my geo updates
      Provider.of<MyTelemetry>(context, listen: false).addListener(() {
        MyTelemetry telemetry =
            Provider.of<MyTelemetry>(context, listen: false);
        if (state == ClientState.authenticated) {
          sendTelemetry(telemetry.geo, telemetry.fuel);
        }
      });
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
          authResponse(payload);
          break;
        case "updateProfileResponse":
          updateProfileResponse(payload);
          break;
        case "groupInfoResponse":
          groupInfoResponse(payload);
          break;
        case "chatLogResponse":
          chatLogResponse(payload);
          break;
        case "pilotsStatusResponse":
          pilotsStatusResponse(payload);
          break;
        case "joinGroupResponse":
          joinGroupResponse(payload);
          break;
        case "chatMessage":
          chatMessage(payload);
          break;
        case "pilotTelemetry":
          pilotTelemetry(payload);
          break;
        case "pilotJoinedGroup":
          pilotJoinedGroup(payload);
          break;
        case "pilotLeftGroup":
          pilotLeftGroup(payload);
          break;
        case "flightPlanSync":
          flightPlanSync(payload);
          break;
        case "flightPlanUpdate":
          flightPlanUpdate(payload);
          break;
        case "pilotSelectedWaypoint":
          pilotSelectedWaypoint(payload);
          break;
        default:
          debugPrint("RX-unknown action: ${jsonMsg["action"]}");
      }
    } else {
      debugPrint("There was some error! ${response}");
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
        "secret_id": profile.secretID,
        "pilot": {
          "id": profile.id,
          "name": profile.name,
          "avatar_hash": profile.avatarHash
        },
        "group": Provider.of<Group>(context, listen: false).loadGroup()
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
        "avatar_hash": profile.avatarHash
      },
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
    sendToAWS("pilotTelemetry", {
      "timestamp": geo.time,
      "pilot_id": "", // backend will fill this in
      "telemetry": {
        "geoPos": {
          "latitude": geo.lat,
          "longitude": geo.lng,
          "altitude": geo.alt,
        },
        "fuel": fuel,
      },
    });
  }

  void requestGroupInfo(String? reqGroupID) {
    if (reqGroupID != null && reqGroupID != "") {
      sendToAWS("groupInfoRequest", {"group": reqGroupID});
    }
  }

  void requestChatLog(String reqGroupID, int since) {
    sendToAWS("chatLogRequest", {
      "time_window": {
        // no farther back than 30 minutes
        "start": max(since, DateTime.now().millisecondsSinceEpoch - 6000 * 30),
        "end": DateTime.now().millisecondsSinceEpoch
      },
      "group": reqGroupID
    });
  }

  void joinGroup(String reqGroupID) {
    sendToAWS("joinGroupRequest", {
      "group": reqGroupID,
    });
    debugPrint("Requesting Join Group $reqGroupID");
  }

  void leaveGroup(bool promptSplit) {
    // This is just alias to joining an unknown group
    Provider.of<Group>(context, listen: false).currentGroupID = null;
    Provider.of<Chat>(context, listen: false).leftGroup();
    sendToAWS("joinGroupRequest", {"prompt_split": promptSplit});
  }

  void checkPilotsOnline(List<String> pilotIDs) {
    sendToAWS("pilotsStatusRequest", {"pilot_ids": pilotIDs});
  }

  // ############################################################################
  //
  //     Response from Server
  //
  // ############################################################################

  // --- new text message from server
  void chatMessage(Map<String, dynamic> msg) {
    String? currentGroupID =
        Provider.of<Group>(context, listen: false).currentGroupID;
    if (msg["group"] == currentGroupID) {
      Provider.of<Chat>(context, listen: false).processMessageFromServer(msg);
    } else {
      // getting messages from the wrong group!
      debugPrint("Wrong group ID! $currentGroupID, ${msg["group"]}");
    }
  }

  //--- receive location of other pilots
  void pilotTelemetry(Map<String, dynamic> msg) {
    // if we know this pilot, update their telemetry
    Group group = Provider.of<Group>(context, listen: false);
    if (group.hasPilot(msg["pilot_id"])) {
      group.updatePilotTelemetry(
          msg["pilot_id"], msg["telemetry"], msg["timestamp"]);
    } else {
      debugPrint("Unrecognized local pilot ${msg["pilot_id"]}");
      requestGroupInfo(group.currentGroupID);
    }
  }

  // --- new Pilot to group
  void pilotJoinedGroup(Map<String, dynamic> msg) {
    Map<String, dynamic> pilot = msg["pilot"];
    if (pilot["id"] != Provider.of<Profile>(context, listen: false).id) {
      // update pilots with new info
      Group group = Provider.of<Group>(context, listen: false);
      group.processNewPilot(pilot);
    }
  }

  // --- Pilot left group
  void pilotLeftGroup(Map<String, dynamic> msg) {
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
  void flightPlanSync(Map<String, dynamic> msg) {
    // TODO: hook back up to flightPlan provider
    // planManager.plans["group"].replaceData(msg["flight_plan"]);
  }

  // --- Process an update to group flight plan
  void flightPlanUpdate(Map<String, dynamic> msg) {
    // make backup copy of the plan

    // update the plan
    switch (msg["action"]) {
      case WaypointAction.delete:
        // Delete a waypoint
        Provider.of<FlightPlan>(context, listen: false)
            .removeWaypoint(msg["index"]);
        break;
      case WaypointAction.add:
        // insert a new waypoint
        Provider.of<FlightPlan>(context, listen: false)
            .addWaypoint(msg["index"], Waypoint.fromJson(msg["data"]));
        break;
      case WaypointAction.sort:
        // Reorder a waypoint
        Provider.of<FlightPlan>(context, listen: false)
            .sortWaypoint(msg["index"], msg["new_index"]);
        break;
      case WaypointAction.modify:
        // Make updates to a waypoint
        if (msg["data"] != null) {
          Provider.of<FlightPlan>(context, listen: false)
              .replaceWaypoint(msg["index"], Waypoint.fromJson(msg["data"]));
        }
        break;
      case WaypointAction.none:
        // no-op
        break;
    }

    String hash = hashFlightPlanData(
        Provider.of<FlightPlan>(context, listen: false).waypoints);
    if (hash != msg["hash"]) {
      // DE-SYNC ERROR
      // restore backup
      debugPrint("Group Flightplan De-sync!  $hash  ${msg['hash']}");

      // we are out of sync!
      // TODO: re-enable when hashing is fixed
      // requestGroupInfo(currentGroupID);
    }
  }

  // --- Process Pilot Waypoint selections
  void pilotSelectedWaypoint(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(context, listen: false);

    debugPrint("${msg["pilot_id"]} selected wp: ${msg["index"]}");
    if (group.hasPilot(msg["pilot_id"])) {
      group.pilotSelectedWaypoint(msg["pilot_id"], msg["index"]);
    } else {
      // we don't have this pilot?
      requestGroupInfo(group.currentGroupID);
    }
  }

  void authResponse(Map<String, dynamic> msg) {
    if (msg["status"] != ErrorCode.success.index) {
      state = ClientState.connected;
      debugPrint("Error Authenticating: ${msg["status"]}");
    } else {
      debugPrint("Authenticated!");
      state = ClientState.authenticated;

      // compare API version
      // TODO: should have big warning banners for this
      if (msg["api_version"] > apiVersion) {
        debugPrint("Client is out of date!");
      } else if (msg["api_version"] < apiVersion) {
        debugPrint("Server is out of date!");
      }

      Profile profile = Provider.of<Profile>(context, listen: false);
      profile.updateID(msg["pilot_id"], msg["secret_id"]);

      // join the provided group
      Group group = Provider.of<Group>(context, listen: false);
      group.currentGroupID = msg["group"];
      requestGroupInfo(group.currentGroupID);

      // update profile
      if (msg["pilot_meta_hash"] != profile.hash) {
        debugPrint("Server had outdate profile meta.");
        pushProfile(profile);
      }
    }
  }

  void updateProfileResponse(Map<String, dynamic> msg) {
    if (msg["status"] != ErrorCode.success.index) {
      debugPrint("Error Updating profile ${msg['status']}");
    }
  }

  void groupInfoResponse(Map<String, dynamic> msg) {
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
        if (jsonPilot["id"] !=
            Provider.of<Profile>(context, listen: false).id) {
          group.processNewPilot(jsonPilot);
        }
      });

      // TODO: replace all the flightPlan data (and show prompt?)
      //  planManager.plans["group"].replaceData(msg["flight_plan"]);
    }
  }

  void chatLogResponse(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(context, listen: false);
    if (msg["status"] != ErrorCode.success.index) {
      debugPrint("ChatLogRequest Failed ${msg['status']}");
    } else {
      if (msg["group"] == group.currentGroupID) {
        // TODO: process chat messages
        // Object.values(msg["msgs"]).forEach((msg: api.chatMessage) => {
        //     // handle each message
        //     chat.processchatMessage(msg, true);
        // });
      } else {
        debugPrint("Wrong group ID! $group.currentGroupID, ${msg["group"]}");
      }
    }
  }

  void pilotsStatusResponse(Map<String, dynamic> msg) {
    if (msg["status"] != ErrorCode.success.index) {
      debugPrint("Error getting pilot statuses ${msg['status']}");
    } else {
      // TODO: should this be throttled?
      Map<String, bool> _pilots = msg["pilots_online"];
      _pilots.forEach((pilotId, online) => {
            // TODO: process contact status
            // contacts[pilotId].online = online;
            // updateContactEntry(pilot_id);
          });
    }
  }

  void joinGroupResponse(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(context, listen: false);
    if (msg["status"] != ErrorCode.success.index) {
      // not a valid group
      if (msg["status"] == ErrorCode.invalidId.index) {
        debugPrint("Attempted to join invalid group ${msg["group"]}");
      } else if (msg["status"] == ErrorCode.noop.index &&
          msg["group"] == group.currentGroupID) {
        // we were already in this group... update anyway
        group.currentGroupID = msg["group"];
      } else {
        debugPrint("Error joining group ${msg['status']}");
      }
    } else {
      // successfully joined group
      group.currentGroupID = msg["group"];
      requestGroupInfo(group.currentGroupID);

      // TODO: get chat history?
      // requestChatLog(groupID, chat.last_msg_timestamp);
    }
  }
}
