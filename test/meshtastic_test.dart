import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/models/mesh_message.dart';
import 'package:xcnav/models/meshtastic_proto.dart';
import 'package:xcnav/models/protobuf_lite.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/notifications.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/views/map/link_status_icon.dart';
import 'package:xcnav/views/view_chat.dart';

import 'mock_providers.dart';

void main() {
  group("protobuf_lite", () {
    test("varint round trip, including negative int32", () {
      final msg = PbMessage()
        ..setVarint(1, 0)
        ..setVarint(2, 300)
        ..setVarint(3, 0xFFFFFFFF)
        ..setVarint(4, -5);
      final decoded = PbMessage.decode(msg.encode());
      expect(decoded.getInt(1), 0);
      expect(decoded.getInt(2), 300);
      expect(decoded.getInt(3), 0xFFFFFFFF);
      expect(decoded.getInt(4)!.toSigned(32), -5);
    });

    test("known encoding", () {
      // From the protobuf docs: field 1 = 150 -> 08 96 01
      expect((PbMessage()..setVarint(1, 150)).encode(), [0x08, 0x96, 0x01]);
      // field 2 = "testing"
      expect((PbMessage()..setString(2, "testing")).encode(),
          [0x12, 0x07, 0x74, 0x65, 0x73, 0x74, 0x69, 0x6e, 0x67]);
    });

    test("fixed32, float, and nested messages", () {
      final inner = PbMessage()..setString(1, "hi");
      final msg = PbMessage()
        ..setFixed32(1, 0xFFFFFFFF)
        ..setMessage(2, inner)
        ..setFixed32(3, 0x40490FDB); // 3.1415927f
      final decoded = PbMessage.decode(msg.encode());
      expect(decoded.getInt(1), 0xFFFFFFFF);
      expect(decoded.getMessage(2)!.getString(1), "hi");
      expect(decoded.getFloat(3), closeTo(3.14159, 0.0001));
    });

    test("unknown fields survive edits", () {
      final original = PbMessage()
        ..setVarint(1, 1)
        ..setString(50, "keep me")
        ..setFixed32(51, 1234);
      final edited = PbMessage.decode(original.encode())..setVarint(1, 2);
      final decoded = PbMessage.decode(edited.encode());
      expect(decoded.getInt(1), 2);
      expect(decoded.getString(50), "keep me");
      expect(decoded.getInt(51), 1234);
      // Field order is kept
      expect(decoded.fields.map((e) => e.number).toList(), [1, 50, 51]);
    });

    test("malformed data throws FormatException", () {
      expect(() => PbMessage.decode([0x12, 0x05, 0x01]), throwsFormatException);
      expect(() => PbMessage.decode([0x08, 0x80]), throwsFormatException);
    });
  });

  group("meshtastic_proto", () {
    test("want_config", () {
      expect(PbMessage.decode(buildWantConfig(1234)).getInt(ToRadioField.wantConfigId), 1234);
    });

    test("packet layout", () {
      final bytes = buildToRadioPacket(
          id: 42, to: meshBroadcastAddr, portnum: xcNavPortNum, payload: [1, 2, 3], wantAck: true, hopLimit: 3);
      final packet = PbMessage.decode(bytes).getMessage(ToRadioField.packet)!;
      expect(packet.getInt(MeshPacketField.to), meshBroadcastAddr);
      expect(packet.getInt(MeshPacketField.id), 42);
      expect(packet.getInt(MeshPacketField.channel), 0);
      expect(packet.getInt(MeshPacketField.hopLimit), 3);
      expect(packet.getBool(MeshPacketField.wantAck), true);
      final data = packet.getMessage(MeshPacketField.decoded)!;
      expect(data.getInt(DataField.portnum), xcNavPortNum);
      expect(data.getBytes(DataField.payload), [1, 2, 3]);
    });

    test("group channel is deterministic and fits Meshtastic limits", () {
      final a = MeshGroupChannel.forGroup("AbC123");
      final b = MeshGroupChannel.forGroup("abc123");
      final c = MeshGroupChannel.forGroup("xyz789");
      expect(a.name, b.name);
      expect(a.psk, b.psk);
      expect(a.groupTag, b.groupTag);
      expect(a.name, isNot(c.name));
      expect(a.psk, isNot(c.psk));
      expect(utf8.encode(a.name).length, lessThanOrEqualTo(11));
      expect(a.psk.length, 32);
    });

    test("preset change keeps the rest of the LoRa config", () {
      final lora = PbMessage()
        ..setBool(LoRaConfigField.usePreset, true)
        ..setVarint(LoRaConfigField.modemPreset, MeshPreset.longFast.value)
        ..setVarint(LoRaConfigField.region, 1)
        ..setVarint(LoRaConfigField.hopLimit, 3)
        ..setBool(LoRaConfigField.txEnabled, true);
      expect(loraWithPreset(lora, MeshPreset.longFast), isNull);

      final changed = loraWithPreset(lora, MeshPreset.mediumFast)!;
      expect(changed.getInt(LoRaConfigField.modemPreset), MeshPreset.mediumFast.value);
      expect(changed.getInt(LoRaConfigField.region), 1);
      expect(changed.getInt(LoRaConfigField.hopLimit), 3);
      expect(changed.getBool(LoRaConfigField.txEnabled), true);
      // Original untouched
      expect(lora.getInt(LoRaConfigField.modemPreset), MeshPreset.longFast.value);

      // Hop limit is forced, even when the preset already matches
      final moreHops = lora.copy()..setVarint(LoRaConfigField.hopLimit, 7);
      final fixed = loraWithPreset(moreHops, MeshPreset.longFast)!;
      expect(fixed.getInt(LoRaConfigField.hopLimit), meshHopLimit);
      expect(fixed.getInt(LoRaConfigField.region), 1);
      expect(loraWithPreset(lora.copy()..remove(LoRaConfigField.hopLimit), MeshPreset.longFast), isNotNull);
    });

    test("primary channel is set once, keeping unrelated settings", () {
      final group = MeshGroupChannel.forGroup("abc123");
      final moduleSettings = PbMessage()..setVarint(1, 13);
      final current = PbMessage()
        ..setVarint(ChannelField.index, 0)
        ..setMessage(
            ChannelField.settings,
            PbMessage()
              ..setBytes(ChannelSettingsField.psk, [1])
              ..setBool(ChannelSettingsField.uplinkEnabled, true)
              ..setMessage(7, moduleSettings))
        ..setVarint(ChannelField.role, ChannelRole.primary);

      final updated = primaryChannelForGroup(current, group)!;
      final settings = updated.getMessage(ChannelField.settings)!;
      expect(updated.getInt(ChannelField.role), ChannelRole.primary);
      expect(settings.getString(ChannelSettingsField.name), group.name);
      expect(settings.getBytes(ChannelSettingsField.psk), group.psk);
      expect(settings.getBool(ChannelSettingsField.uplinkEnabled), false);
      expect(settings.getMessage(7)!.getInt(1), 13);

      // Already configured -> nothing to do
      expect(primaryChannelForGroup(PbMessage.decode(updated.encode()), group), isNull);
      // A radio with no primary channel yet
      expect(primaryChannelForGroup(null, group), isNotNull);
    });

    test("every preset maps to a unique LoRa value", () {
      expect(MeshPreset.values.map((e) => e.value).toSet().length, MeshPreset.values.length);
      expect(MeshPreset.fromValue(0), MeshPreset.longFast);
      expect(MeshPreset.fromValue(99), isNull);
    });
  });

  group("mesh_message", () {
    const tag = 0xBEEF;
    // Receiver clock, a few seconds after the sender
    const now = 1700000005000;

    test("telemetry round trip", () {
      const msg = MeshTelemetry(tag, lat: 37.1234567, lng: -122.7654321, alt: 1234.4, timestamp: 1700000000999);
      final bytes = msg.encode();
      expect(bytes.length, 13);
      final decoded = MeshMessage.decode(bytes, now: now) as MeshTelemetry;
      expect(decoded.groupTag, tag);
      // ~1-2m
      expect(decoded.lat, closeTo(37.1234567, 1.1e-5));
      expect(decoded.lng, closeTo(-122.7654321, 2.2e-5));
      expect(decoded.alt, 1234);
      expect(decoded.timestamp, 1700000000000);
    });

    test("telemetry at the edges of the map", () {
      for (final (lat, lng) in [(90.0, 180.0), (-90.0, -180.0), (0.0, 0.0), (-33.9, 151.2)]) {
        final decoded =
            MeshMessage.decode(MeshTelemetry(tag, lat: lat, lng: lng, alt: -50, timestamp: now).encode(), now: now)
                as MeshTelemetry;
        expect(decoded.lat, closeTo(lat, 1.1e-5));
        expect(decoded.lng, closeTo(lng, 2.2e-5));
        expect(decoded.alt, -50);
      }
    });

    test("truncated timestamps expand to the nearest time", () {
      for (final sent in [now, now - 3000, now + 3000, now - 9 * 3600 * 1000, now + 9 * 3600 * 1000]) {
        final decoded =
            MeshMessage.decode(MeshTelemetry(tag, lat: 0, lng: 0, alt: 0, timestamp: sent).encode(), now: now)
                as MeshTelemetry;
        expect(decoded.timestamp, sent - sent % 1000);
      }
      // Across a 16 bit rollover
      final rollover = (0x10000 * 26000) * 1000;
      final decoded = MeshMessage.decode(
          MeshTelemetry(tag, lat: 0, lng: 0, alt: 0, timestamp: rollover - 2000).encode(),
          now: rollover + 2000) as MeshTelemetry;
      expect(decoded.timestamp, rollover - 2000);
    });

    test("chat round trip and truncation", () {
      final decoded = MeshMessage.decode(
          const MeshChat(tag, timestamp: 1700000000000, emergency: true, text: "Héllo 🪂").encode(),
          now: now) as MeshChat;
      expect(decoded.text, "Héllo 🪂");
      expect(decoded.emergency, true);
      expect(decoded.timestamp, 1700000000000);

      final long = "🪂" * 100;
      final bytes = MeshChat(tag, timestamp: 0, emergency: false, text: long).encode();
      expect(bytes.length, lessThanOrEqualTo(meshMaxPayload));
      final truncated = (MeshMessage.decode(bytes) as MeshChat).text;
      expect(long.startsWith(truncated), true);
      expect(truncated.contains("�"), false);
    });

    test("quick phrases are sent as one byte", () {
      for (final phrase in meshQuickPhrases) {
        final bytes = MeshChat(tag, timestamp: now, emergency: false, text: phrase).encode();
        expect(bytes.length, 7);
        expect((MeshMessage.decode(bytes, now: now) as MeshChat).text, phrase);
      }
      // Every phrase in the chat menu has a code
      for (final phrase in quickchat.where((e) => e.isNotEmpty)) {
        expect(meshQuickPhrases, contains(phrase));
      }
    });

    test("pilot info round trip", () {
      final decoded =
          MeshMessage.decode(const MeshPilotInfo(tag, id: "abc-123", name: "Ünïcode Pilot").encode()) as MeshPilotInfo;
      expect(decoded.id, "abc-123");
      expect(decoded.name, "Ünïcode Pilot");
      expect(decoded.avatarHash, isNull);
    });

    test("other messages round trip", () {
      expect((MeshMessage.decode(const MeshPilotInfoRequest(tag, nodeNum: 0xDEADBEEF).encode()) as MeshPilotInfoRequest)
          .nodeNum, 0xDEADBEEF);
      expect((MeshMessage.decode(const MeshSelectWaypoint(tag, waypointId: "wp1").encode()) as MeshSelectWaypoint)
          .waypointId, "wp1");
      expect((MeshMessage.decode(const MeshSelectWaypoint(tag, waypointId: null).encode()) as MeshSelectWaypoint)
          .waypointId, isNull);
      final delete = MeshMessage.decode(
          MeshWaypointUpdate(tag, action: WaypointAction.delete.index, waypoint: {"id": "wp1"}).encode())
          as MeshWaypointUpdate;
      expect(delete.action, WaypointAction.delete.index);
      expect(delete.waypoint, {"id": "wp1"});
    });

    test("waypoint path arrives exactly as sent, and fits far more points than json", () {
      // A ~15km path with a point every ~500m
      final path = Waypoint(
          name: "Ridge run",
          latlngs: List.generate(30, (i) => LatLng(37.123456 + i * 0.0041 + (i % 3) * 0.00071, -122.654321 - i * 0.0037)),
          color: 0xFF2196F3);
      final json = path.toJson();
      final bytes = MeshWaypointUpdate(tag, action: WaypointAction.update.index, waypoint: json).encode();
      expect(bytes.length, lessThanOrEqualTo(meshMaxPayload));
      expect(bytes.length, lessThan(utf8.encode(jsonEncode(json)).length / 3));

      final decoded = MeshMessage.decode(bytes) as MeshWaypointUpdate;
      expect(decoded.waypoint, json);
      final rebuilt = Waypoint.fromJson(decoded.waypoint);
      expect(rebuilt.latlng, path.latlng.map((e) => LatLng(roundToDigits(e.latitude, 6), roundToDigits(e.longitude, 6))));

      // Single point waypoint with an icon and no color
      final pin = Waypoint(name: "LZ", latlngs: [const LatLng(-33.9, 151.2)], icon: "paraglider").toJson();
      final pinBytes = MeshWaypointUpdate(tag, action: WaypointAction.update.index, waypoint: pin).encode();
      expect((MeshMessage.decode(pinBytes) as MeshWaypointUpdate).waypoint, pin);
    });

    test("rejects garbage", () {
      const v = meshProtocolVersion << 5;
      expect(MeshMessage.decode([]), isNull);
      expect(MeshMessage.decode([((meshProtocolVersion + 1) << 5) | 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), isNull);
      // Truncated telemetry
      expect(MeshMessage.decode([v | MeshMessageType.telemetry.value, 0, 0, 1, 2]), isNull);
      // Unknown type
      expect(MeshMessage.decode([v | 31, 0, 0]), isNull);
      // Unknown quick phrase
      expect(MeshMessage.decode([v | MeshMessageType.chat.value, 0, 0, 0, 0, 0x2, 250]), isNull);
      // Waypoint claiming more points than it has
      expect(MeshMessage.decode([v | MeshMessageType.waypointUpdate.value, 0, 0, 1, 0, 0, 0, 100, 2, 2]), isNull);
    });
  });

  group("dedupe", () {
    test("chat from both links is delivered once", () {
      final deduper = ChatDeduper();
      expect(deduper.isDuplicate("p1", "hello", 1700000000123, now: 0), false);
      // Mesh copy has 1s resolution
      expect(deduper.isDuplicate("p1", "hello", 1700000000000, now: 100), true);
      // Different pilot, text, or a later repeat are new messages
      expect(deduper.isDuplicate("p2", "hello", 1700000000000, now: 100), false);
      expect(deduper.isDuplicate("p1", "hello!", 1700000000000, now: 100), false);
      expect(deduper.isDuplicate("p1", "hello", 1700000060000, now: 100), false);
    });

    test("chat truncated by the mesh still matches", () {
      final deduper = ChatDeduper();
      final long = "a" * 400;
      final meshText = utf8.decode(truncateUtf8(long, MeshChat.maxTextBytes));
      expect(deduper.isDuplicate("p1", meshText, 1000, now: 0), false);
      expect(deduper.isDuplicate("p1", long, 1000, now: 0), true);
    });

    test("chat memory expires", () {
      final deduper = ChatDeduper(window: const Duration(minutes: 1));
      expect(deduper.isDuplicate("p1", "hi", 1000, now: 0), false);
      expect(deduper.isDuplicate("p1", "hi", 1000, now: 120000), false);
    });

    test("telemetry only moves forward", () {
      final deduper = TelemetryDeduper();
      expect(deduper.accept("p1", 10500), true);
      expect(deduper.accept("p1", 10000), false); // same second from mesh
      expect(deduper.accept("p1", 9000), false); // older
      expect(deduper.accept("p2", 9000), true);
      expect(deduper.accept("p1", 13000), true);
      deduper.clear();
      expect(deduper.accept("p1", 9000), true);
    });
  });

  group("client", () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
    });

    testWidgets("messages arriving over cellular and mesh are de-duped", (tester) async {
      SharedPreferences.setMockInitialValues({
        "profile.name": "Me",
        "profile.id": "me1",
        "profile.secretID": "secret",
      });
      setFocus(true); // skip OS notifications

      late Client client;
      late Group group;
      late ChatMessages chat;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ActivePlan(), lazy: false),
          // ignore: unnecessary_cast
          ChangeNotifierProvider(create: (_) => MockPlans() as Plans, lazy: false),
          ChangeNotifierProvider(create: (_) => Profile(), lazy: false),
          ChangeNotifierProvider(create: (_) => Group(), lazy: false),
          ChangeNotifierProvider(create: (_) => ChatMessages(), lazy: false),
          // ignore: unnecessary_cast
          ChangeNotifierProvider(create: (context) => MockClient(context) as Client, lazy: false),
        ],
        child: Builder(builder: (context) {
          client = Provider.of<Client>(context, listen: false);
          group = Provider.of<Group>(context, listen: false);
          chat = Provider.of<ChatMessages>(context, listen: false);
          return Container();
        }),
      ));

      group.currentGroupID = "abc123";
      final tag = MeshGroupChannel.forGroup("abc123").groupTag;
      const bobNode = 0x1234;
      final now = DateTime.now().millisecondsSinceEpoch;

      // --- Bob introduces himself on the mesh
      client.handleMeshPacket(bobNode, const MeshPilotInfo(0, id: "bob", name: "Bob").encode());
      expect(group.hasPilot("bob"), false, reason: "wrong group tag is ignored");
      client.handleMeshPacket(bobNode, MeshPilotInfo(tag, id: "bob", name: "Bob").encode());
      expect(group.pilots["bob"]?.name, "Bob");

      // --- Chat arrives on mesh, then the same message over cellular
      client.handleMeshPacket(bobNode, MeshChat(tag, timestamp: now, emergency: false, text: "thermal here").encode());
      client.handleChatMessage(
          {"group_id": "abc123", "pilot_id": "bob", "text": "thermal here", "timestamp": now, "emergency": false});
      expect(chat.messages.length, 1);
      expect(chat.messages.first.pilotId, "bob");

      // --- Telemetry arrives on cellular, then the same fix over mesh
      final fixTime = now - (now % 1000) + 400;
      client.handlePilotTelemetry({
        "pilot_id": "bob",
        "timestamp": fixTime,
        "telemetry": {
          "gps": {"lat": 37.0, "lng": -122.0, "alt": 500.0}
        },
      });
      client.handleMeshPacket(
          bobNode, MeshTelemetry(tag, lat: 37.0, lng: -122.0, alt: 500, timestamp: fixTime).encode());
      expect(group.pilots["bob"]!.flightTrace.length, 1);

      // --- A newer fix over mesh only
      client.handleMeshPacket(
          bobNode, MeshTelemetry(tag, lat: 37.001, lng: -122.0, alt: 510, timestamp: fixTime + 30000).encode());
      expect(group.pilots["bob"]!.flightTrace.length, 2);
      expect(group.pilots["bob"]!.geo!.lat, closeTo(37.001, 1.1e-5));

      // --- Selected waypoint over mesh
      client.handleMeshPacket(bobNode, MeshSelectWaypoint(tag, waypointId: "wp1").encode());
      expect(group.pilots["bob"]!.selectedWp, "wp1");
    });

    testWidgets("joining a group with no server joins locally", (tester) async {
      SharedPreferences.setMockInitialValues({});

      late Client client;
      late Group group;
      late BuildContext ctx;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ActivePlan(), lazy: false),
          // ignore: unnecessary_cast
          ChangeNotifierProvider(create: (_) => MockPlans() as Plans, lazy: false),
          ChangeNotifierProvider(create: (_) => Profile(), lazy: false),
          ChangeNotifierProvider(create: (_) => Group(), lazy: false),
          ChangeNotifierProvider(create: (_) => ChatMessages(), lazy: false),
          // ignore: unnecessary_cast
          ChangeNotifierProvider(create: (context) => MockClient(context) as Client, lazy: false),
        ],
        child: Builder(builder: (context) {
          ctx = context;
          client = Provider.of<Client>(context, listen: false);
          group = Provider.of<Group>(context, listen: false);
          return Container();
        }),
      ));

      // MockClient never authenticates without a profile name
      expect(client.state, isNot(ClientState.authenticated));
      client.joinGroup(ctx, "XYZ789");
      expect(group.currentGroupID, "xyz789");
    });

    testWidgets("cellular icon shows connecting, then disconnected", (tester) async {
      SharedPreferences.setMockInitialValues({});

      late Client client;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ActivePlan(), lazy: false),
          // ignore: unnecessary_cast
          ChangeNotifierProvider(create: (_) => MockPlans() as Plans, lazy: false),
          ChangeNotifierProvider(create: (_) => Profile(), lazy: false),
          ChangeNotifierProvider(create: (_) => Group(), lazy: false),
          ChangeNotifierProvider(create: (_) => ChatMessages(), lazy: false),
          // ignore: unnecessary_cast
          ChangeNotifierProvider(create: (context) => MockClient(context) as Client, lazy: false),
        ],
        child: Builder(builder: (context) {
          client = Provider.of<Client>(context, listen: false);
          return Container();
        }),
      ));

      // Socket open, not yet authenticated
      expect(client.state, ClientState.connected);
      expect(cellularStatusIcon(client), Icons.signal_cellular_connected_no_internet_4_bar);

      // First few failed attempts still count as connecting
      client.reconnectionWait = 1;
      client.state = ClientState.disconnected;
      expect(cellularStatusIcon(client), Icons.signal_cellular_connected_no_internet_4_bar);
      await tester.pump(const Duration(seconds: 2));

      // Repeated failures show disconnected
      client.reconnectionWait = Client.connectingAttempts + 1;
      client.state = ClientState.disconnected;
      expect(cellularStatusIcon(client), Icons.signal_cellular_nodata);
      expect(cellularStatusColor(client), Colors.red);
      await tester.pump(const Duration(seconds: Client.connectingAttempts + 2));
    });
  });
}
