import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/ble_devices/ble_device_meshtastic.dart';

// --- Models
import 'package:xcnav/models/error_code.dart';
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/models/ga.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/mesh_message.dart';
import 'package:xcnav/models/meshtastic_proto.dart';
import 'package:xcnav/models/waypoint.dart';

// --- Providers
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/chat_messages.dart';

import 'package:xcnav/endpoint.dart';
import 'package:xcnav/services/ble_service.dart' show bleDeviceMeshtastic;
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/util.dart';

enum ClientState {
  disconnected,
  connected,
  authenticated,
}

const double apiVersion = 7.1;

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

/// Most waypoints shared over the mesh at once by [Client.pushWaypoints]
const int maxMeshWaypointSync = 8;

/// Group client. Talks to the group through the cellular server and/or a Meshtastic radio.
///
/// Outgoing messages go out on every enabled link. Incoming messages may arrive on both, so they are de-duped.
class Client with ChangeNotifier {
  WebSocket? socket;
  ClientState _state = ClientState.disconnected;
  bool _connecting = false;
  Timer? _reconnectTimer;

  int telemetrySkips = 0;
  DateTime? _lastAirplanesSent;

  /// Min time between sending our ADSB reports to the server
  static const Duration airplanesObservedInterval = Duration(seconds: 3);

  /// Only send ADSB reports within this range of us (meters), so the server isn't flooded with distant planes.
  static const double airplanesObservedRange = 8000;
  int reconnectionWait = 0;

  final BuildContext globalContext;

  final ChatDeduper _chatDeduper = ChatDeduper();
  final TelemetryDeduper _telemetryDeduper = TelemetryDeduper();

  // --- Meshtastic
  /// Meshtastic node number -> pilot id
  final Map<int, String> _meshPilots = {};
  final Map<int, DateTime> _meshInfoRequested = {};
  String? _meshGroupId;
  bool _wasMeshReady = false;
  DateTime? _lastMeshTelemetry;
  DateTime? _lastMeshAnnounce;
  String? _lastMeshAnnounceKey;
  Timer? _meshAnnounceTimer;
  final Random _rand = Random();

  Client(this.globalContext) {
    debugPrint("Build Client");
    _setupMesh();
    connect();
  }

  /// Cellular can only be turned off while a Meshtastic radio is attached, so the group link can't silently vanish.
  bool get cellularEnabled => !bleDeviceMeshtastic.isActive || settingsMgr.clientUseCellular.value;

  bool get meshEnabled => settingsMgr.clientUseMesh.value;

  bool get meshReady => meshEnabled && bleDeviceMeshtastic.isReady;

  /// Failed connection attempts before cellular is shown as disconnected rather than connecting.
  static const int connectingAttempts = 3;

  /// Cellular link is coming up: socket open but not yet authenticated, or still within the first few attempts.
  bool get cellularConnecting =>
      cellularEnabled &&
      (state == ClientState.connected || (state == ClientState.disconnected && reconnectionWait <= connectingAttempts));

  void sendToAWS(String action, dynamic payload) {
    debugPrint("TX: ${jsonEncode({"action": action, "body": payload})}");
    if (socket != null) {
      socket!.add(jsonEncode({"action": action, "body": payload}));
    }
  }

  bool _watchingProfile = false;

  /// Watch updates to Profile. Only registers once, even across reconnects.
  void watchProfile() {
    if (_watchingProfile) return;
    _watchingProfile = true;
    Provider.of<Profile>(globalContext, listen: false).addListener(() {
      Profile profile = Provider.of<Profile>(globalContext, listen: false);
      if (state == ClientState.connected) {
        authenticate(profile);
      } else if (state == ClientState.authenticated && profile.name != null) {
        // Just need to update server with new profile
        pushProfile(profile);
      }
    });
  }

  ClientState get state => _state;
  set state(ClientState newState) {
    _state = newState;
    if (newState == ClientState.disconnected) {
      final oldSocket = socket;
      socket = null;
      oldSocket?.close();
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      if (cellularEnabled) {
        debugPrint("Reconnecting in ${reconnectionWait}sec...");
        _reconnectTimer = Timer(Duration(seconds: reconnectionWait), (() => connect()));
      }
    }
    notifyListeners();
  }

  void connect() async {
    if (!cellularEnabled || _connecting || socket != null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    reconnectionWait += 1;

    if (serverEndpoint == null) {
      debugPrint("Waiting for server to be selected.");
      state = ClientState.disconnected;
    } else {
      _connecting = true;
      HttpOverrides.global = MyHttpOverrides(serverEndpoint!.cert);
      WebSocket.connect(serverEndpoint!.apiUrl, headers: {"authorizationToken": serverEndpoint!.token})
          .then((newSocket) {
        _connecting = false;
        if (!cellularEnabled) {
          // Cellular was turned off while we were connecting.
          newSocket.close();
          return;
        }
        reconnectionWait = 0;

        socket = newSocket;
        state = ClientState.connected;
        debugPrint("Connected!");

        socket!.listen(handleResponse, onError: (errorRaw) {
          debugPrint("RX-error: $errorRaw");
          if (socket == newSocket) state = ClientState.disconnected;
        }, onDone: () {
          debugPrint("RX-done");
          if (socket == newSocket) state = ClientState.disconnected;
        });
        if (globalContext.mounted) {
          Profile profile = Provider.of<Profile>(globalContext, listen: false);
          if (nameValidator(profile.name) == null) {
            authenticate(profile);
          }

          watchProfile();

          // Register Callbacks to waypoints
          Provider.of<ActivePlan>(globalContext, listen: false).onWaypointAction = waypointsUpdate;
          Provider.of<ActivePlan>(globalContext, listen: false).onSelectWaypoint = selectWaypoint;
        }
      }).onError((error, stackTrace) {
        _connecting = false;
        debugPrint("Failed to connect! $error");
        state = ClientState.disconnected;
      });
    }
  }

  /// Called when a link is enabled/disabled or the Meshtastic radio changes state.
  void _onLinksChanged() {
    if (cellularEnabled) {
      if (socket == null && !_connecting && _reconnectTimer == null) {
        reconnectionWait = 0;
        connect();
      }
    } else if (socket != null || _reconnectTimer != null) {
      debugPrint("Cellular client disabled.");
      state = ClientState.disconnected;
    }

    if (bleDeviceMeshtastic.status.value == MeshtasticStatus.noGroup) {
      _restoreSavedGroup();
    }

    if (meshReady && !_wasMeshReady) _meshHello();
    _wasMeshReady = meshReady;

    notifyListeners();
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
        case "airplanesObserved":
          handleAirplanesObserved(payload);
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    sendToAWS("chatMessage", {
      "timestamp": timestamp,
      "group_id": group.currentGroupID, // target group
      "pilot_id": "", // sender (filled in by backend)
      "text": text,
      "emergency": isEmergency ?? false,
    });
    final tag = _meshTag;
    if (tag != null) {
      _meshSend(MeshChat(tag, timestamp: timestamp, emergency: isEmergency ?? false, text: text), wantAck: true);
    }
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

    final tag = _meshTag;
    final now = clock.now();
    if (tag != null && (_lastMeshTelemetry == null || now.difference(_lastMeshTelemetry!) >= meshTelemetryInterval)) {
      _lastMeshTelemetry = now;
      _meshSend(MeshTelemetry(tag, lat: geo.lat, lng: geo.lng, alt: geo.alt, timestamp: geo.time));
    }
  }

  /// Echo GA reports from our own ADSB receiver to the server. (Not sent over the mesh.)
  /// Throttled; only the latest report per plane, within [airplanesObservedRange] of [observer], is sent.
  void sendAirplanesObserved(ADSB adsb, Geo observer) {
    final now = clock.now();
    if (_lastAirplanesSent != null && now.difference(_lastAirplanesSent!) < airplanesObservedInterval) return;
    _lastAirplanesSent = now;
    final airplanes = adsb.takeObserved(near: observer.latlng, range: airplanesObservedRange);
    if (airplanes.isEmpty || state != ClientState.authenticated) return;
    sendToAWS("airplanesObserved", {
      "airplanes": airplanes.map((e) => e.toJson()).toList(),
    });
  }

  void requestGroupInfo(String? reqGroupID) {
    if (reqGroupID != null && reqGroupID != "") {
      sendToAWS("groupInfoRequest", {"group_id": reqGroupID});
    }
  }

  void _joinGroup(String reqGroupID) {
    if (state == ClientState.authenticated) {
      sendToAWS("joinGroupRequest", {
        "group_id": reqGroupID.toLowerCase(),
      });
      debugPrint("Requesting Join Group $reqGroupID");
    } else {
      // No server to ask, so join locally. This still lets us fly together over the mesh,
      // and the saved group is sent to the server when we authenticate.
      debugPrint("Joining group $reqGroupID locally (no server)");
      Provider.of<Group>(globalContext, listen: false).currentGroupID = reqGroupID.toLowerCase();
    }
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
    final tag = _meshTag;
    if (tag != null) {
      _meshSend(MeshWaypointUpdate(tag,
          action: action.index, waypoint: action == WaypointAction.delete ? {"id": waypoint.id} : waypoint.toJson()));
    }
  }

  /// Share all our waypoints with the group.
  void pushWaypoints() {
    _pushWaypointsCellular();

    // Mesh has no full sync, so send each waypoint as an update. (Ones with long paths won't fit in a packet.)
    final tag = _meshTag;
    if (tag != null) {
      for (final each in Provider.of<ActivePlan>(globalContext, listen: false)
          .waypoints
          .values
          .where((element) => !element.ephemeral)
          .take(maxMeshWaypointSync)) {
        _meshSend(MeshWaypointUpdate(tag, action: WaypointAction.update.index, waypoint: each.toJson()));
      }
    }
  }

  void _pushWaypointsCellular() {
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
    final tag = _meshTag;
    if (tag != null) _meshSend(MeshSelectWaypoint(tag, waypointId: waypointID));
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
      _deliverChat(parseAsString(msg["pilot_id"]) ?? "", msg);
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
      _applyPilotTelemetry(pilotId, msg["telemetry"], msg["timestamp"]);
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

  // --- GA reports from other pilots' ADSB receivers
  void handleAirplanesObserved(Map<String, dynamic> msg) {
    final airplanes = msg["airplanes"];
    if (airplanes is! List) return;
    Provider.of<ADSB>(globalContext, listen: false).addServerPlanes(airplanes.map(GA.fromJson).nonNulls);
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

        // Covers avatars set before we had an id, and uploads that previously failed.
        profile.ensureAvatarUploaded();

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
        _pushWaypointsCellular();
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
      if (myTelemetry.geo != null) sendTelemetry(myTelemetry.geo!);
    }
  }

  // ############################################################################
  //
  //     Shared between links (de-dupe)
  //
  // ############################################################################

  void _deliverChat(String pilotId, Map<String, dynamic> msg) {
    final now = clock.now().millisecondsSinceEpoch;
    final senderTimestamp = msg["timestamp"] is int ? msg["timestamp"] as int : now;
    if (_chatDeduper.isDuplicate(pilotId, msg["text"] ?? "", senderTimestamp, now: now)) {
      debugPrint("Dropped duplicate chat message from $pilotId");
      return;
    }
    final group = Provider.of<Group>(globalContext, listen: false);
    Provider.of<ChatMessages>(globalContext, listen: false)
        .processMessageFromServer(group.pilots[pilotId]?.name ?? "", msg);
  }

  void _applyPilotTelemetry(String pilotId, dynamic telemetry, int timestamp) {
    if (_telemetryDeduper.accept(pilotId, timestamp)) {
      Provider.of<Group>(globalContext, listen: false).updatePilotTelemetry(pilotId, telemetry, timestamp);
    }
  }

  // ############################################################################
  //
  //     Meshtastic
  //
  // ############################################################################

  void _setupMesh() {
    bleDeviceMeshtastic.onReceive = handleMeshPacket;
    bleDeviceMeshtastic.status.addListener(_onLinksChanged);
    bleDeviceMeshtastic.attached.addListener(_onLinksChanged);
    settingsMgr.clientUseCellular.listenable.addListener(_onLinksChanged);
    settingsMgr.clientUseMesh.listenable.addListener(_onLinksChanged);

    // Mesh channel follows the group.
    final group = Provider.of<Group>(globalContext, listen: false);
    group.addListener(() {
      final groupId = (group.currentGroupID?.isEmpty ?? true) ? null : group.currentGroupID;
      if (groupId != _meshGroupId) {
        _meshGroupId = groupId;
        _meshPilots.clear();
        _telemetryDeduper.clear();
        bleDeviceMeshtastic.setGroupId(groupId);
        // Already on the mesh, so introduce ourselves on the new channel once the radio has switched.
        // (Otherwise we say hello when the radio becomes ready.)
        if (groupId != null && meshReady) Timer(const Duration(seconds: 3), _meshHello);
      }
    });

    Provider.of<Profile>(globalContext, listen: false).addListener(_announceOnMesh);
  }

  /// Without the server we never get told our group, so fall back on the last one we were in.
  void _restoreSavedGroup() {
    final group = Provider.of<Group>(globalContext, listen: false);
    if (group.currentGroupID == null && state != ClientState.authenticated) {
      final saved = group.loadGroup();
      if (saved != null && saved.isNotEmpty) {
        debugPrint("Restoring saved group $saved for mesh.");
        group.currentGroupID = saved;
      }
    }
  }

  /// [MeshGroupChannel.groupTag] if we can send on the mesh
  int? get _meshTag => meshReady ? bleDeviceMeshtastic.groupChannel?.groupTag : null;

  /// How often we send our telemetry over the mesh. Backs off as the group grows to keep the channel clear.
  Duration get meshTelemetryInterval {
    final pilots = bleDeviceMeshtastic.numNodesHeard + 1;
    return bleDeviceMeshtastic.preset.telemetryInterval * max(1.0, pilots / 4);
  }

  void _meshSend(MeshMessage msg, {bool wantAck = false}) {
    final payload = msg.encode();
    if (payload.length > meshMaxPayload) {
      debugPrint("Mesh: ${msg.type.name} too large (${payload.length} bytes), not sent.");
      return;
    }
    bleDeviceMeshtastic.send(payload, wantAck: wantAck);
  }

  /// Introduce ourselves and ask who else is on the channel.
  void _meshHello() {
    final tag = _meshTag;
    if (tag == null) return;
    _announceOnMesh(force: true);
    _meshSend(MeshPilotInfoRequest(tag, nodeNum: 0));
    // Re-announce now and then for anyone who missed it.
    _meshAnnounceTimer ??= Timer.periodic(const Duration(minutes: 5), (_) => _announceOnMesh());
  }

  /// Broadcast our pilot info so others can map our node to our pilot.
  void _announceOnMesh({bool force = false}) {
    final tag = _meshTag;
    final profile = Provider.of<Profile>(globalContext, listen: false);
    if (tag == null || profile.name == null) return;

    final info = MeshPilotInfo(tag, id: _myPilotId(profile), name: profile.name!, avatarHash: profile.avatarHash);
    final key = "${info.id}|${info.name}|${info.avatarHash}";
    final now = clock.now();
    final sinceLast = _lastMeshAnnounce == null ? null : now.difference(_lastMeshAnnounce!);
    // Rate limit, but always let changes through.
    if (key == _lastMeshAnnounceKey &&
        sinceLast != null &&
        sinceLast < (force ? const Duration(seconds: 3) : const Duration(seconds: 15))) {
      return;
    }
    _lastMeshAnnounce = now;
    _lastMeshAnnounceKey = key;
    _meshSend(info);
  }

  /// Pilots who've never reached the server have no id, so fall back on the radio's node number.
  String _myPilotId(Profile profile) => profile.id ?? "mesh-${bleDeviceMeshtastic.myNodeNum?.toRadixString(16) ?? ""}";

  void _requestMeshPilotInfo(int nodeNum) {
    final tag = _meshTag;
    final now = clock.now();
    final last = _meshInfoRequested[nodeNum];
    if (tag == null || (last != null && now.difference(last) < const Duration(minutes: 1))) return;
    _meshInfoRequested[nodeNum] = now;
    _meshSend(MeshPilotInfoRequest(tag, nodeNum: nodeNum));
  }

  void handleMeshPacket(int fromNode, Uint8List payload) {
    final channel = bleDeviceMeshtastic.groupChannel;
    final msg = MeshMessage.decode(payload);
    if (!meshEnabled || channel == null || msg == null) return;
    if (msg.groupTag != channel.groupTag) {
      debugPrint("Mesh: message from another group");
      return;
    }

    final group = Provider.of<Group>(globalContext, listen: false);
    final myId = Provider.of<Profile>(globalContext, listen: false).id;
    final pilotId = _meshPilots[fromNode];

    switch (msg) {
      case MeshPilotInfo info:
        if (info.id == myId) return;
        _meshPilots[fromNode] = info.id;
        final existing = group.pilots[info.id];
        if (existing == null || existing.name != info.name || existing.avatarHash != info.avatarHash) {
          group.processNewPilot(info.id, {"id": info.id, "name": info.name, "avatarHash": info.avatarHash});
        }
        break;
      case MeshPilotInfoRequest request:
        if (request.nodeNum == 0 || request.nodeNum == bleDeviceMeshtastic.myNodeNum) {
          // Jitter so everyone doesn't answer at once.
          Timer(Duration(milliseconds: _rand.nextInt(3000)), () => _announceOnMesh(force: request.nodeNum != 0));
        }
        break;
      case MeshTelemetry telemetry:
        if (pilotId == null || !group.hasPilot(pilotId)) {
          _requestMeshPilotInfo(fromNode);
          return;
        }
        _applyPilotTelemetry(
            pilotId,
            {
              "gps": {"lat": telemetry.lat, "lng": telemetry.lng, "alt": telemetry.alt}
            },
            telemetry.timestamp);
        break;
      case MeshChat chat:
        if (pilotId == null) _requestMeshPilotInfo(fromNode);
        // Deliver even if we don't know who sent it yet. It could be an emergency.
        final senderId = pilotId ?? "mesh-${fromNode.toRadixString(16)}";
        _deliverChat(senderId,
            {"timestamp": chat.timestamp, "pilot_id": senderId, "text": chat.text, "emergency": chat.emergency});
        break;
      case MeshSelectWaypoint select:
        if (pilotId == null || !group.hasPilot(pilotId)) {
          _requestMeshPilotInfo(fromNode);
          return;
        }
        group.pilotSelectedWaypoint(pilotId, select.waypointId);
        break;
      case MeshWaypointUpdate update:
        _applyMeshWaypointUpdate(update);
        break;
    }
  }

  void _applyMeshWaypointUpdate(MeshWaypointUpdate update) {
    final plan = Provider.of<ActivePlan>(globalContext, listen: false);
    try {
      if (update.action == WaypointAction.delete.index) {
        final waypointId = parseAsString(update.waypoint["id"]);
        if (waypointId != null) plan.backendRemoveWaypoint(waypointId);
      } else if (update.action == WaypointAction.update.index) {
        plan.updateWaypoint(Waypoint.fromJson(update.waypoint), shouldCallback: false);
      }
    } catch (error) {
      debugPrint("Mesh: bad waypoint update: $error");
    }
  }
}
