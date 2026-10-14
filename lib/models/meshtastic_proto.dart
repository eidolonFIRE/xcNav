import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xcnav/models/protobuf_lite.dart';

// Field numbers for the subset of the Meshtastic protobufs xcNav uses.
// Source of truth: https://github.com/meshtastic/protobufs (mesh.proto, admin.proto, config.proto, channel.proto)

class ToRadioField {
  static const int packet = 1;
  static const int wantConfigId = 3;
  static const int disconnect = 4;
}

class FromRadioField {
  static const int id = 1;
  static const int packet = 2;
  static const int myInfo = 3;
  static const int nodeInfo = 4;
  static const int config = 5;
  static const int logRecord = 6;
  static const int configCompleteId = 7;
  static const int rebooted = 8;
  static const int moduleConfig = 9;
  static const int channel = 10;
  static const int queueStatus = 11;
}

class MyNodeInfoField {
  static const int myNodeNum = 1;
}

class MeshPacketField {
  static const int from = 1; // fixed32
  static const int to = 2; // fixed32
  static const int channel = 3;
  static const int decoded = 4;
  static const int encrypted = 5;
  static const int id = 6; // fixed32
  static const int rxTime = 7; // fixed32
  static const int rxSnr = 8; // float
  static const int hopLimit = 9;
  static const int wantAck = 10;
  static const int priority = 11;
  static const int rxRssi = 12;
}

class DataField {
  static const int portnum = 1;
  static const int payload = 2;
  static const int wantResponse = 3;
}

class PortNum {
  static const int textMessage = 1;
  static const int admin = 6;

  /// Meshtastic reserves 256-511 for private applications.
  static const int privateApp = 256;
}

class AdminField {
  static const int setChannel = 33;
  static const int setConfig = 34;
  static const int beginEditSettings = 64;
  static const int commitEditSettings = 65;
}

class ConfigField {
  static const int lora = 6;
}

class LoRaConfigField {
  static const int usePreset = 1;
  static const int modemPreset = 2;
  static const int region = 7;
  static const int hopLimit = 8;
  static const int txEnabled = 9;
}

class ChannelField {
  static const int index = 1;
  static const int settings = 2;
  static const int role = 3;
}

class ChannelRole {
  static const int disabled = 0;
  static const int primary = 1;
  static const int secondary = 2;
}

class ChannelSettingsField {
  static const int psk = 2;
  static const int name = 3;
  static const int uplinkEnabled = 5;
  static const int downlinkEnabled = 6;
}

/// Destination address for broadcast packets
const int meshBroadcastAddr = 0xFFFFFFFF;

/// The port xcNav client messages are sent on.
const int xcNavPortNum = PortNum.privateApp;

/// Hops every xcNav packet (and the radio's own broadcasts) may take.
const int meshHopLimit = 3;

/// Max size of `Data.payload` in a single LoRa packet.
const int meshMaxPayload = 233;

/// Meshtastic LoRa modem presets, in order of increasing range (and decreasing speed).
///
/// [telemetryInterval] is how often we send our position over the mesh with this preset.
/// Slower presets use more airtime per packet so we have to back off further.
enum MeshPreset {
  shortTurbo(8, "Short Turbo", Duration(seconds: 5)),
  shortFast(6, "Short Fast", Duration(seconds: 8)),
  shortSlow(5, "Short Slow", Duration(seconds: 10)),
  mediumFast(4, "Medium Fast", Duration(seconds: 15)),
  mediumSlow(3, "Medium Slow", Duration(seconds: 20)),
  longFast(0, "Long Fast", Duration(seconds: 30)),
  longModerate(7, "Long Moderate", Duration(seconds: 45)),
  longSlow(1, "Long Slow", Duration(seconds: 60));

  /// `Config.LoRaConfig.ModemPreset` enum value
  final int value;
  final String label;
  final Duration telemetryInterval;

  const MeshPreset(this.value, this.label, this.telemetryInterval);

  static MeshPreset? fromValue(int? value) {
    for (final each in MeshPreset.values) {
      if (each.value == value) return each;
    }
    return null;
  }
}

/// The Meshtastic channel a group flies on. Every member derives the same channel from the group code.
class MeshGroupChannel {
  /// Channel name. Meshtastic limits this to 11 bytes.
  final String name;

  /// AES256 key
  final Uint8List psk;

  /// Short tag included in every xcNav mesh message so stale packets from a previous group are ignored.
  final int groupTag;

  MeshGroupChannel._(this.name, this.psk, this.groupTag);

  factory MeshGroupChannel.forGroup(String groupId) {
    final id = groupId.toLowerCase();
    final nameHash = sha256.convert(utf8.encode("xcNav-mesh-name:$id")).toString();
    final psk = Uint8List.fromList(sha256.convert(utf8.encode("xcNav-mesh-psk:$id")).bytes);
    final tagHash = sha256.convert(utf8.encode("xcNav-mesh-tag:$id")).bytes;
    return MeshGroupChannel._("xc${nameHash.substring(0, 9)}", psk, (tagHash[0] << 8) | tagHash[1]);
  }
}

// ############################################################################
//
//     Builders
//
// ############################################################################

Uint8List buildWantConfig(int nonce) => (PbMessage()..setVarint(ToRadioField.wantConfigId, nonce)).encode();

Uint8List buildToRadioPacket({
  required int id,
  required int to,
  required int portnum,
  required List<int> payload,
  int channel = 0,
  bool wantAck = false,
  bool wantResponse = false,
  int? hopLimit,
}) {
  final data = PbMessage()
    ..setVarint(DataField.portnum, portnum)
    ..setBytes(DataField.payload, payload);
  if (wantResponse) data.setBool(DataField.wantResponse, true);

  final packet = PbMessage()
    ..setFixed32(MeshPacketField.to, to)
    ..setVarint(MeshPacketField.channel, channel)
    ..setMessage(MeshPacketField.decoded, data)
    ..setFixed32(MeshPacketField.id, id);
  if (hopLimit != null) packet.setVarint(MeshPacketField.hopLimit, hopLimit);
  if (wantAck) packet.setBool(MeshPacketField.wantAck, true);

  return (PbMessage()..setMessage(ToRadioField.packet, packet)).encode();
}

PbMessage adminBeginEdit() => PbMessage()..setBool(AdminField.beginEditSettings, true);

PbMessage adminCommitEdit() => PbMessage()..setBool(AdminField.commitEditSettings, true);

PbMessage adminSetLoRaConfig(PbMessage lora) =>
    PbMessage()..setMessage(AdminField.setConfig, PbMessage()..setMessage(ConfigField.lora, lora));

PbMessage adminSetChannel(PbMessage channel) => PbMessage()..setMessage(AdminField.setChannel, channel);

/// Returns a copy of [lora] using [preset] and [meshHopLimit], or null if it already does.
PbMessage? loraWithPreset(PbMessage lora, MeshPreset preset) {
  if (lora.getBool(LoRaConfigField.usePreset) &&
      (lora.getInt(LoRaConfigField.modemPreset) ?? 0) == preset.value &&
      lora.getInt(LoRaConfigField.hopLimit) == meshHopLimit) {
    return null;
  }
  return lora.copy()
    ..setBool(LoRaConfigField.usePreset, true)
    ..setVarint(LoRaConfigField.modemPreset, preset.value)
    ..setVarint(LoRaConfigField.hopLimit, meshHopLimit);
}

/// Returns the primary channel configured for [group], or null if [current] already matches.
///
/// Unrelated settings on the existing channel (e.g. module settings) are preserved.
PbMessage? primaryChannelForGroup(PbMessage? current, MeshGroupChannel group) {
  final settings = current?.getMessage(ChannelField.settings) ?? PbMessage();
  final psk = settings.getBytes(ChannelSettingsField.psk) ?? Uint8List(0);
  final matches = current?.getInt(ChannelField.role) == ChannelRole.primary &&
      settings.getString(ChannelSettingsField.name) == group.name &&
      psk.length == group.psk.length &&
      Iterable.generate(psk.length).every((i) => psk[i] == group.psk[i]) &&
      !settings.getBool(ChannelSettingsField.uplinkEnabled) &&
      !settings.getBool(ChannelSettingsField.downlinkEnabled);
  if (matches) return null;

  final newSettings = settings.copy()
    ..setBytes(ChannelSettingsField.psk, group.psk)
    ..setString(ChannelSettingsField.name, group.name)
    // Group traffic stays on the radio link.
    ..remove(ChannelSettingsField.uplinkEnabled)
    ..remove(ChannelSettingsField.downlinkEnabled);
  return PbMessage()
    ..setVarint(ChannelField.index, 0)
    ..setMessage(ChannelField.settings, newSettings)
    ..setVarint(ChannelField.role, ChannelRole.primary);
}
