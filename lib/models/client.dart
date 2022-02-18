import 'dart:convert';
import 'dart:js';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/models/error_code.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/flight_plan.dart';
import 'package:xcnav/providers/profile.dart';

enum WaypointAction {
  none,
  add,
  modify,
  delete,
  sort,
}

const double apiVersion = 3.5;

class Client {
  late IO.Socket socket;

  String? currentGroupID;
  Map<String, Pilot> pilots = {};

  Client(BuildContext context) {
    // Dart client
    IO.Socket socket = IO.io('https://xcnav-server.herokuapp.com');

    socket.io.options["secure"] = true;
    socket.io.options["withCredentials"] = true;

    socket.onConnect((_) {
      print('connect');
      socket.emit('msg', 'test');
    });
    socket.onDisconnect((_) => print('disconnect'));

    setupListeners(context);

    if (Provider.of<Profile>(context, listen: false).secretID == null ||
        Provider.of<Profile>(context, listen: false).id == null) {
      register(Provider.of<Profile>(context, listen: false).name,
          Provider.of<Profile>(context, listen: false).id ?? "");
    } else {
      login(Provider.of<Profile>(context, listen: false).secretID!,
          Provider.of<Profile>(context, listen: false).id!);
    }
  }

  bool hasPilot(String pilotID) => pilots.containsKey(pilotID);

  void processNewPilot(dynamic p) {
    Pilot newPilot = Pilot(p["id"], p["name"], Geo());
    Uint8List imgBits = base64Decode(p["avatar"]);
    newPilot.avatar = Image.memory(imgBits);
    pilots[p["id"]] = newPilot;
  }

  // ############################################################################
  //
  //     Async Receive from Server
  //
  // ############################################################################

  void setupListeners(BuildContext context) {
    // --- new text message from server
    socket.on("TextMessage", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["group_id"] == currentGroupID) {
        // TODO: process msg
        // chat.processTextMessage(msg);
      } else {
        // getting messages from the wrong group!
        print("Wrong group ID! $currentGroupID, ${msg["group_id"]}");
      }
    });

    //--- receive location of other pilots
    socket.on("PilotTelemetry", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      // if we know this pilot, update their telemetry
      if (hasPilot(msg["pilot_id"])) {
        pilots[msg["pilot_id"]]!
            .updateTelemetry(msg["telemetry"], msg["timestamp"]);
      } else {
        print("Unrecognized local pilot ${msg["pilot_id"]}");
        if (currentGroupID != null) {
          requestGroupInfo(currentGroupID!);
        }
      }
    });

    // --- new Pilot to group
    socket.on("PilotJoinedGroup", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["pilot"].id != Provider.of<Profile>(context, listen: false).id) {
        // update pilots with new info
        processNewPilot(msg["pilot"]);
      }
    });

    // --- Pilot left group
    socket.on("PilotLeftGroup", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["pilot_id"] == Provider.of<Profile>(context, listen: false).id)
        return;
      pilots.remove(msg["pilot_id"]);
      if (msg["new_group_id"] != "") {
        // TODO: prompt yes/no should we follow them to new group
      }
    });

    // --- Full flight plan sync
    socket.on("FlightPlanSync", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      // TODO: hook back up to flightPlan provider
      // planManager.plans["group"].replaceData(msg["flight_plan"]);
    });

    // --- Process an update to group flight plan
    socket.on("FlightPlanUpdate", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
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
        print("Group Flightplan De-sync!  $hash  ${msg['hash']}");

        // we are out of sync!
        // TODO: re-enable when hashing is fixed
        // requestGroupInfo(currentGroupID);
      }
    });

    // --- Process Pilot Waypoint selections
    socket.on("PilotWaypointSelections", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      msg.forEach((otherPilotId, wp) {
        print("$otherPilotId selected wp: $wp");
        if (hasPilot(otherPilotId)) {
          pilots[otherPilotId]!.selectedWaypoint = wp;
        } else {
          // we don't have this pilot?
          if (currentGroupID != null) {
            requestGroupInfo(currentGroupID!);
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
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["status"]) {
        // TODO: handle error
        // msg["status"] (ErrorCode)
        print("Error Registering ${msg['status']}");
      } else {
        // update my ID
        Provider.of<Profile>(context, listen: false)
            .updateID(msg["pilot_id"], msg["secret_id"]);

        // proceed to login
        login(Provider.of<Profile>(context, listen: false).secretID!,
            Provider.of<Profile>(context, listen: false).id!);
      }
    });

    socket.on("LoginResponse", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["status"]) {
        if (msg["status"] == ErrorCode.invalidSecretId ||
            msg["status"] == ErrorCode.invalidId) {
          // we aren't registered on this server
          register(Provider.of<Profile>(context, listen: false).name,
              Provider.of<Profile>(context, listen: false).id ?? "");
          return;
        } else {
          print("Error Logging in.");
        }
      } else {
        // compare API version
        // TODO: should have big warning banners for this
        if (msg["api_version"] > apiVersion) {
          print("Client is out of date!");
        } else if (msg["api_version"] < apiVersion) {
          print("Server is out of date!");
        }

        // update profile
        if (msg["pilot_meta_hash"] !=
            Provider.of<Profile>(context, listen: false).hash) {
          print("Server had outdate profile meta.");
          pushProfile(Provider.of<Profile>(context, listen: false));
        }

        // follow invite link

        // TODO: Now that we're logged in, time to follow invite link if we have one
        //       Then, update our own invite link.
        // updateInviteLink(publicID);
      }
    });

    socket.on("UpdateProfileResponse", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["status"]) {
        print("Error Updating profile ${msg['status']}");
      }
    });

    socket.on("GroupInfoResponse", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["status"]) {
        print("Error getting group info ${msg['status']}");
      } else {
        // ignore if it's not a group I'm in
        if (msg["group_id"] != currentGroupID) {
          print("Received info for another group.");
          return;
        }

        // TODO: support map layers in the future
        // update map layers from group
        // msg["map_layers"].forEach((layer: string) => {
        //     // TODO: handle map_layers from the group
        // });

        // update pilots with new info
        msg["pilots"].forEach((jsonPilot) => {processNewPilot(jsonPilot)});

        // TODO: replace all the flightPlan data (and show prompt?)
        //  planManager.plans["group"].replaceData(msg["flight_plan"]);
      }
    });

    socket.on("ChatLogResponse", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["status"]) {
        print("ChatLogRequest Failed ${msg['status']}");
      } else {
        if (msg["group_id"] == currentGroupID) {
          // TODO: process chat messages
          // Object.values(msg["msgs"]).forEach((msg: api.TextMessage) => {
          //     // handle each message
          //     chat.processTextMessage(msg, true);
          // });
        } else {
          print("Wrong group ID! $currentGroupID, ${msg["group_id"]}");
        }
      }
    });

    socket.on("PilotsStatusResponse", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["status"]) {
        print("Error getting pilot statuses ${msg['status']}");
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
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["status"]) {
        if (msg["status"] == ErrorCode.noop && currentGroupID == null) {
          // It's ok, we were pretty sure we weren't in a group anyway.
        } else {
          print("Error leaving group ${msg['status']}");
        }
      } else {
        currentGroupID = msg["group_id"];
      }
    });

    socket.on("JoinGroupResponse", (jsonMsg) {
      dynamic msg = jsonDecode(jsonMsg);
      if (msg["status"]) {
        // not a valid group
        if (msg["status"] == ErrorCode.invalidId) {
          print("Attempted to join invalid group ${msg["group_id"]}");
        } else if (msg["status"] == ErrorCode.noop &&
            msg["group_id"] == currentGroupID) {
          // we were already in this group... update anyway
          currentGroupID = msg["group_id"];
        } else {
          print("Error joining group ${msg['status']}");
        }
      } else {
        // successfully joined group
        currentGroupID = msg["group_id"];

        // TODO: get chat history?
        // requestChatLog(groupID, chat.last_msg_timestamp);
      }
    });
  }

  // ############################################################################
  //
  //     Async Send to Server
  //
  // ############################################################################

  // --- send a text message
  void sendTextMessage(String text, {bool? isEmergency}) {
    socket.emit("TextMessage", {
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "index": 0, // TODO: what should index be?
      "group_id": currentGroupID, // target group
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
  // void updateWaypoint(msg: api.FlightPlanUpdate) {
  //     print("TX waypoint update:",  msg)
  //     socket.emit("FlightPlanUpdate", msg);
  // }

  // void sendWaypointSelection() {
  //     const msg: api.PilotWaypointSelections = {}
  //     msg[publicID] = me.current_waypoint;
  //     socket.emit("PilotWaypointSelections", msg);
  // }

  // ############################################################################
  //
  //     Register
  //
  // ############################################################################
  void register(String name, String publicID) {
    socket.emit("RegisterRequest", {
      "pilot": {
        "id": publicID,
        "name": name,
      }
    });
  }

  // ############################################################################
  //
  //     Login
  //
  // ############################################################################
  void login(String secretID, String publicID) {
    socket.emit("LoginRequest", {
      "secret_id": secretID,
      "pilot_id": publicID,
    });
  }

  // ############################################################################
  //
  //     Update Profile
  //
  // ############################################################################
  void pushProfile(Profile profile) {
    socket.emit("UpdateProfileRequest", {
      "pilot": {
        "id": profile.id,
        "name": profile.name,
        "avatar": profile.avatarRaw,
      },
      "secret_id": profile.secretID
    });
  }

  // ############################################################################
  //
  //     Get Group Info
  //
  // ############################################################################
  void requestGroupInfo(String reqGroupID) {
    socket.emit("GroupInfoRequest", {"group_id": reqGroupID});
  }

  // ############################################################################
  //
  //     Get Chat Log
  //
  // ############################################################################
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

  // ############################################################################
  //
  //     Join a group
  //
  // ############################################################################
  void joinGroup(String reqGroupID) {
    socket.emit("JoinGroupRequest", {
      "target_id": reqGroupID,
    });
    print("Requesting Join Group $reqGroupID");
  }

  // ############################################################################
  //
  //     Leave group
  //
  // ############################################################################
  void leaveGroup(bool promptSplit) {
    socket.emit("LeaveGroupRequest", {"prompt_split": promptSplit});
  }

  // ############################################################################
  //
  //     Get Pilot Statuses
  //
  // ############################################################################
  void checkPilotsOnline(List<String> pilotIDs) {
    socket.emit("PilotsStatusRequest", {"pilot_ids": pilotIDs});
  }
}
