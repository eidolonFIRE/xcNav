import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';
// import 'package:web_socket_channel/status.dart' as status;

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
  registering,
  registered,
  loggingIn,
  loggedIn,
}

const double apiVersion = 3.8;

class Client {
  WebSocket? socket;
  ClientState state = ClientState.disconnected;

  final BuildContext context;

  Client(this.context) {
    debugPrint("Build Client");
    connect();
  }

  void sendToAWS(String action, dynamic payload) {
    if (socket != null) {
      socket!.add(jsonEncode({"action": action, "body": payload}));
    }
  }

  void connect() async {
    WebSocket.connect(
            "wss://cilme82sm3.execute-api.us-west-1.amazonaws.com/production")
        // "cilme82sm3.execute-api.us-west-1.amazonaws.com/production")
        .then((newSocket) {
      socket = newSocket;
      debugPrint("Connected!");

      socket!.listen(handleResponse, onError: (errorRaw) {
        debugPrint("RX-error: $errorRaw");
      }, onDone: () {
        debugPrint("RX-done");
      });

      initConnection();

      // Watch updates to Profile
      Provider.of<Profile>(context, listen: false).addListener(() {
        Profile profile = Provider.of<Profile>(context, listen: false);
        if (state == ClientState.connected) {
          // When client was inialized, we weren't ready... attempt initial login again
          if (profile.secretID == null) {
            if (profile.name != null) {
              // Providing public ID on register is optional
              register(profile.name!, profile.id ?? "");
            }
          } else if (profile.secretID != null && profile.id != null) {
            login(profile.secretID!, profile.id!);
          }
        } else if (state == ClientState.loggedIn) {
          // Just need to update server with new profile
          pushProfile(profile);
        }
      });

      // Subscribe to my geo updates
      Provider.of<MyTelemetry>(context, listen: false).addListener(() {
        MyTelemetry telemetry =
            Provider.of<MyTelemetry>(context, listen: false);
        sendTelemetry(telemetry.geo, telemetry.fuel);
      });
    });
  }

  void handleResponse(dynamic response) {
    final jsonMsg = json.decode(response);
    debugPrint("RX: $jsonMsg");

    Map<String, dynamic> payload = jsonMsg["body"];

    switch (jsonMsg["action"]) {
      case "registerResponse":
        registerResponse(payload);
        break;
      case "loginResponse":
        loginResponse(payload);
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
      case "leaveGroupResponse":
        leaveGroupResponse(payload);
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
      case "pilotWaypointSelections":
        pilotWaypointSelections(payload);
        break;
      default:
        debugPrint("RX-unknown action: ${jsonMsg["action"]}");
    }
  }

  void initConnection() async {
    Profile profile = Provider.of<Profile>(context, listen: false);
    if (profile.secretID == null) {
      if (profile.name != null) {
        // Providing public ID on register is optional
        register(profile.name!, profile.id ?? "");
      }
    } else if (profile.secretID != null && profile.id != null) {
      login(profile.secretID!, profile.id!);
    }
  }

  // ############################################################################
  //
  //     Requests
  //
  // ############################################################################

  void register(String name, String publicID) {
    if (state != ClientState.registering) {
      debugPrint("Registering) $name, $publicID");
      sendToAWS("register", {
        "pilot": {
          "id": publicID,
          "name": name,
        }
      });
    } else {
      debugPrint("... already trying to register!");
    }
  }

  void login(String secretID, String publicID) {
    if (state != ClientState.loggingIn) {
      debugPrint("Logging in) $publicID, $secretID");
      sendToAWS("login", {
        "secret_id": secretID,
        "pilot_id": publicID,
      });
    } else {
      debugPrint("... already trying to log in!");
    }
  }

  void pushProfile(Profile profile) {
    debugPrint("Push Profile: ${profile.name}, ${profile.id}");
    sendToAWS("updateProfile", {
      "pilot": {
        "id": profile.id,
        "name": profile.name,
        "avatar":
            profile.avatarRaw != null ? base64Encode(profile.avatarRaw!) : "",
      },
      "secret_id": profile.secretID
    });
  }

  void sendchatMessage(String text, {bool? isEmergency}) {
    Group group = Provider.of<Group>(context, listen: false);
    sendToAWS("chatMessage", {
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "index": 0, // TODO: what should index be?
      "group_id": group.currentGroupID, // target group
      "pilot_id": "", // sender
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

  void requestGroupInfo(String reqGroupID) {
    sendToAWS("groupInfoRequest", {"group_id": reqGroupID});
  }

  void requestChatLog(String reqGroupID, int since) {
    sendToAWS("chatLogRequest", {
      "time_window": {
        // no farther back than 30 minutes
        "start": max(since, DateTime.now().millisecondsSinceEpoch - 6000 * 30),
        "end": DateTime.now().millisecondsSinceEpoch
      },
      "group_id": reqGroupID
    });
  }

  void joinGroup(String reqGroupID) {
    sendToAWS("joinGroupRequest", {
      "group_id": reqGroupID,
    });
    debugPrint("Requesting Join Group $reqGroupID");
  }

  void leaveGroup(bool promptSplit) {
    sendToAWS("leaveGroupRequest", {"prompt_split": promptSplit});
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
    if (msg["group_id"] == currentGroupID) {
      Provider.of<Chat>(context, listen: false).processMessageFromServer(msg);
    } else {
      // getting messages from the wrong group!
      debugPrint("Wrong group ID! $currentGroupID, ${msg["group_id"]}");
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
      if (group.currentGroupID != null) {
        requestGroupInfo(group.currentGroupID!);
      }
    }
  }

  // --- new Pilot to group
  void pilotJoinedGroup(Map<String, dynamic> msg) {
    if (msg["pilot"].id != Provider.of<Profile>(context, listen: false).id) {
      // update pilots with new info
      Group group = Provider.of<Group>(context, listen: false);
      group.processNewPilot(msg["pilot"]);
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
    if (msg["new_group_id"] != "") {
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
  void pilotWaypointSelections(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(context, listen: false);
    msg.forEach((otherPilotId, wp) {
      debugPrint("$otherPilotId selected wp: $wp");
      if (group.hasPilot(otherPilotId)) {
        group.pilotSelectedWaypoint(otherPilotId, wp);
      } else {
        // we don't have this pilot?
        if (group.currentGroupID != null) {
          requestGroupInfo(group.currentGroupID!);
        }
      }
    });
  }

  void registerResponse(Map<String, dynamic> msg) {
    if (msg["status"] != ErrorCode.success.index) {
      // TODO: handle error
      // msg["status"] (ErrorCode)
      debugPrint("Error Registering ${msg['status']}");
      state = ClientState.connected;
    } else {
      // update my ID
      Provider.of<Profile>(context, listen: false)
          .updateID(msg["pilot_id"], msg["secret_id"]);
      debugPrint("Registered!");
      state = ClientState.registered;
    }
  }

  void loginResponse(Map<String, dynamic> msg) {
    if (msg["status"] != ErrorCode.success.index) {
      state = ClientState.connected;
      if (msg["status"] == ErrorCode.invalidSecretId.index ||
          msg["status"] == ErrorCode.invalidId.index) {
        // we aren't registered on this server
        // TODO: ensure name is set
        Profile profile = Provider.of<Profile>(context, listen: false);
        if (profile.name != null) {
          // Providing public ID is optional here
          register(profile.name!, profile.id ?? "");
        }
        return;
      } else {
        debugPrint("Unhandled error while logging in.");
      }
    } else {
      state = ClientState.loggedIn;

      // join the provided group
      Provider.of<Group>(context, listen: false).currentGroupID =
          msg["group_id"];

      // compare API version
      // TODO: should have big warning banners for this
      if (msg["api_version"] > apiVersion) {
        debugPrint("Client is out of date!");
      } else if (msg["api_version"] < apiVersion) {
        debugPrint("Server is out of date!");
      }

      // update profile
      if (msg["pilot_meta_hash"] !=
          Provider.of<Profile>(context, listen: false).hash) {
        debugPrint("Server had outdate profile meta.");
        pushProfile(Provider.of<Profile>(context, listen: false));
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
      if (msg["group_id"] != group.currentGroupID) {
        debugPrint("Received info for another group.");
        return;
      }

      // TODO: support map layers in the future
      // update map layers from group
      // msg["map_layers"].forEach((layer: string) => {
      //     // TODO: handle map_layers from the group
      // });

      // update pilots with new info
      msg["pilots"].forEach((jsonPilot) => {group.processNewPilot(jsonPilot)});

      // TODO: replace all the flightPlan data (and show prompt?)
      //  planManager.plans["group"].replaceData(msg["flight_plan"]);
    }
  }

  void chatLogResponse(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(context, listen: false);
    if (msg["status"] != ErrorCode.success.index) {
      debugPrint("ChatLogRequest Failed ${msg['status']}");
    } else {
      if (msg["group_id"] == group.currentGroupID) {
        // TODO: process chat messages
        // Object.values(msg["msgs"]).forEach((msg: api.chatMessage) => {
        //     // handle each message
        //     chat.processchatMessage(msg, true);
        // });
      } else {
        debugPrint("Wrong group ID! $group.currentGroupID, ${msg["group_id"]}");
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

  void leaveGroupResponse(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(context, listen: false);
    if (msg["status"] != ErrorCode.success.index) {
      if (msg["status"] == ErrorCode.noop.index &&
          group.currentGroupID == null) {
        // It's ok, we were pretty sure we weren't in a group anyway.
      } else {
        debugPrint("Error leaving group ${msg['status']}");
      }
    } else {
      // This is our new group now
      group.currentGroupID = msg["group_id"];
    }
  }

  void joinGroupResponse(Map<String, dynamic> msg) {
    Group group = Provider.of<Group>(context, listen: false);
    if (msg["status"] != ErrorCode.success.index) {
      // not a valid group
      if (msg["status"] == ErrorCode.invalidId.index) {
        debugPrint("Attempted to join invalid group ${msg["group_id"]}");
      } else if (msg["status"] == ErrorCode.noop.index &&
          msg["group_id"] == group.currentGroupID) {
        // we were already in this group... update anyway
        group.currentGroupID = msg["group_id"];
      } else {
        debugPrint("Error joining group ${msg['status']}");
      }
    } else {
      // successfully joined group
      group.currentGroupID = msg["group_id"];

      // TODO: get chat history?
      // requestChatLog(groupID, chat.last_msg_timestamp);
    }
  }
}
