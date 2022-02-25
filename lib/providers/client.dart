import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

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

const double apiVersion = 3.7;

class Client {
  late IO.Socket socket;
  ClientState state = ClientState.disconnected;

  final BuildContext context;

  Client(this.context) {
    debugPrint("Build Client");

    // socket = IO.io('https://xcnav-server.herokuapp.com');
    // socket = IO.io('http://localhost:8081');
    // socket = IO.io('http://192.168.1.101:8081');
    socket = IO.io('http://192.168.1.101:8081',
        IO.OptionBuilder().setTransports(["websocket"]).build());

    // socket.connect();
    //   "secure": true,
    //   "withCredentials": true,
    // });
    // socket.io.options["secure"] = true;
    // socket.io.options["withCredentials"] = true;

    setupListeners();
  }

  void setupListeners() async {
    socket.onConnect((_) {
      debugPrint('Client Connected');

      state = ClientState.connected;

      Profile profile = Provider.of<Profile>(context, listen: false);

      if (profile.secretID == null) {
        if (profile.name != null) {
          // Providing public ID on register is optional
          register(profile.name!, profile.id ?? "");
        }
      } else if (profile.secretID != null && profile.id != null) {
        login(profile.secretID!, profile.id!);
      }

      setupSocketListeners();
    });
    socket.onDisconnect((_) {
      debugPrint('Client Disconnected');
      state = ClientState.disconnected;
    });

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
      MyTelemetry telemetry = Provider.of<MyTelemetry>(context, listen: false);
      sendTelemetry(telemetry.geo, telemetry.fuel);
    });
  }

  // ############################################################################
  void setupSocketListeners() {
    // --- new text message from server
    socket.on("TextMessage", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
      String? currentGroupID =
          Provider.of<Group>(context, listen: false).currentGroupID;
      if (msg["group_id"] == currentGroupID) {
        Provider.of<Chat>(context, listen: false).processMessageFromServer(msg);
      } else {
        // getting messages from the wrong group!
        debugPrint("Wrong group ID! $currentGroupID, ${msg["group_id"]}");
      }
    });

    //--- receive location of other pilots
    socket.on("PilotTelemetry", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
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
    });

    // --- new Pilot to group
    socket.on("PilotJoinedGroup", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
      if (msg["pilot"].id != Provider.of<Profile>(context, listen: false).id) {
        // update pilots with new info
        Group group = Provider.of<Group>(context, listen: false);
        group.processNewPilot(msg["pilot"]);
      }
    });

    // --- Pilot left group
    socket.on("PilotLeftGroup", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
      if (msg["pilot_id"] == Provider.of<Profile>(context, listen: false).id) {
        // ignore if it's us
        return;
      }
      Group group = Provider.of<Group>(context, listen: false);
      group.removePilot(msg["pilot_id"]);
      if (msg["new_group_id"] != "") {
        // TODO: prompt yes/no should we follow them to new group
      }
    });

    // --- Full flight plan sync
    socket.on("FlightPlanSync", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
      // TODO: hook back up to flightPlan provider
      // planManager.plans["group"].replaceData(msg["flight_plan"]);
    });

    // --- Process an update to group flight plan
    socket.on("FlightPlanUpdate", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
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
    });

    // --- Process Pilot Waypoint selections
    socket.on("PilotWaypointSelections", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
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
    });

    // ############################################################################
    //
    //     Response from Server
    //
    // ############################################################################
    socket.on("RegisterResponse", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;

      if (msg["status"] != ErrorCode.success.index) {
        // TODO: handle error
        // msg["status"] (ErrorCode)
        debugPrint("Error Registering ${msg['status']}");
        state = ClientState.connected;
      } else {
        // update my ID
        Provider.of<Profile>(context, listen: false)
            .updateID(msg["pilot_id"], msg["secret_id"]);

        state = ClientState.registered;
      }
    });

    socket.on("LoginResponse", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
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
          debugPrint("Error Logging in.");
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

        // follow invite link

        // TODO: Now that we're logged in, time to follow invite link if we have one
        //       Then, update our own invite link.
        // updateInviteLink(publicID);
      }
    });

    socket.on("UpdateProfileResponse", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
      if (msg["status"] != ErrorCode.success.index) {
        debugPrint("Error Updating profile ${msg['status']}");
      }
    });

    socket.on("GroupInfoResponse", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
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
        msg["pilots"]
            .forEach((jsonPilot) => {group.processNewPilot(jsonPilot)});

        // TODO: replace all the flightPlan data (and show prompt?)
        //  planManager.plans["group"].replaceData(msg["flight_plan"]);
      }
    });

    socket.on("ChatLogResponse", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
      Group group = Provider.of<Group>(context, listen: false);
      if (msg["status"] != ErrorCode.success.index) {
        debugPrint("ChatLogRequest Failed ${msg['status']}");
      } else {
        if (msg["group_id"] == group.currentGroupID) {
          // TODO: process chat messages
          // Object.values(msg["msgs"]).forEach((msg: api.TextMessage) => {
          //     // handle each message
          //     chat.processTextMessage(msg, true);
          // });
        } else {
          debugPrint(
              "Wrong group ID! $group.currentGroupID, ${msg["group_id"]}");
        }
      }
    });

    socket.on("PilotsStatusResponse", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
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
    });

    socket.on("LeaveGroupResponse", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
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
    });

    socket.on("JoinGroupResponse", (jsonMsg) {
      Map<String, dynamic> msg = jsonMsg;
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
    });
  }

  // ############################################################################
  //
  //     Requests
  //
  // ############################################################################
  void sendTextMessage(String text, {bool? isEmergency}) {
    Group group = Provider.of<Group>(context, listen: false);
    socket.emit("TextMessage", {
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
    socket.emit("PilotTelemetry", {
      "timestamp": geo.time,
      "pilot_id": "",
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

  // TODO: send flight plan changes
  void register(String name, String publicID) {
    if (state != ClientState.registering) {
      debugPrint("Registering) $name, $publicID");
      socket.emit("RegisterRequest", {
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
      socket.emit("LoginRequest", {
        "secret_id": secretID,
        "pilot_id": publicID,
      });
    } else {
      debugPrint("... already trying to log in!");
    }
  }

  void pushProfile(Profile profile) {
    debugPrint("Push Profile: ${profile.name}, ${profile.id}");
    socket.emit("UpdateProfileRequest", {
      "pilot": {
        "id": profile.id,
        "name": profile.name,
        "avatar":
            profile.avatarRaw != null ? base64Encode(profile.avatarRaw!) : "",
      },
      "secret_id": profile.secretID
    });
  }

  void requestGroupInfo(String reqGroupID) {
    socket.emit("GroupInfoRequest", {"group_id": reqGroupID});
  }

  void requestChatLog(String reqGroupID, int since) {
    socket.emit("ChatLogRequest", {
      "time_window": {
        // no farther back than 30 minutes
        "start": max(since, DateTime.now().millisecondsSinceEpoch - 6000 * 30),
        "end": DateTime.now().millisecondsSinceEpoch
      },
      "group_id": reqGroupID
    });
  }

  void joinGroup(String reqGroupID) {
    socket.emit("JoinGroupRequest", {
      "group_id": reqGroupID,
    });
    debugPrint("Requesting Join Group $reqGroupID");
  }

  void leaveGroup(bool promptSplit) {
    socket.emit("LeaveGroupRequest", {"prompt_split": promptSplit});
  }

  void checkPilotsOnline(List<String> pilotIDs) {
    socket.emit("PilotsStatusRequest", {"pilot_ids": pilotIDs});
  }
}
