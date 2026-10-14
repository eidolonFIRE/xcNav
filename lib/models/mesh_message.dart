import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:xcnav/models/meshtastic_proto.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/util.dart';

/// Bump when the over-the-air format changes in an incompatible way. (3 bits)
const int meshProtocolVersion = 1;

/// Header: version (3 bits) + type (5 bits), group tag (2 bytes)
const int _headerLen = 3;

/// Canned chat messages sent as a single byte.
/// APPEND ONLY. The index is what goes over the air, so existing entries must never change or move.
const List<String> meshQuickPhrases = [
  "Waiting here... ⏱️",
  "Let's Gooooo!",
  "Where to? 🤷",
  "Turning back ↩️",
  "Landed ok 🛬",
  "Good Air 🧈",
  "Hazardous ☠️",
  "Emergency: Engine out!",
  "Low fuel ⚠️",
  "Ignore last",
];

enum MeshMessageType {
  telemetry(1),
  chat(2),
  pilotInfo(3),
  pilotInfoRequest(4),
  selectWaypoint(5),
  waypointUpdate(6);

  final int value;
  const MeshMessageType(this.value);
}

/// An xcNav client message sent over Meshtastic.
///
/// LoRa airtime is precious, so these are packed binary rather than the JSON used by the cellular client.
/// The sender is identified by its Meshtastic node number, which is mapped to a pilot via [MeshPilotInfo].
sealed class MeshMessage {
  /// See [MeshGroupChannel.groupTag]
  final int groupTag;

  const MeshMessage(this.groupTag);

  MeshMessageType get type;

  void _encodeBody(_Writer w);

  Uint8List encode() {
    final w = _Writer()
      ..u8((meshProtocolVersion << 5) | type.value)
      ..u16(groupTag);
    _encodeBody(w);
    return w.bytes;
  }

  /// Returns null for malformed packets, unknown types, or other protocol versions.
  ///
  /// [now] (ms since epoch) is used to expand the truncated timestamps. Defaults to the current time.
  static MeshMessage? decode(List<int> data, {int? now}) {
    if (data.length < _headerLen || data[0] >> 5 != meshProtocolVersion) return null;
    now ??= clock.now().millisecondsSinceEpoch;
    final r = _Reader(data);
    final type = r.u8() & 0x1F;
    final tag = r.u16();
    try {
      if (type == MeshMessageType.telemetry.value) {
        return MeshTelemetry(tag,
            lat: _decodeAngle(r.u24(), 90),
            lng: _decodeAngle(r.u24(), 180),
            alt: r.i16().toDouble(),
            timestamp: _expandTime(r.u16(), now));
      } else if (type == MeshMessageType.chat.value) {
        final timestamp = _expandTime(r.u16(), now);
        final flags = r.u8();
        final String text;
        if (flags & 0x2 != 0) {
          final index = r.u8();
          if (index >= meshQuickPhrases.length) return null;
          text = meshQuickPhrases[index];
        } else {
          text = r.restString();
        }
        return MeshChat(tag, timestamp: timestamp, emergency: flags & 0x1 != 0, text: text);
      } else if (type == MeshMessageType.pilotInfo.value) {
        final id = r.str8();
        final name = r.str8();
        final avatarHash = r.str8();
        return MeshPilotInfo(tag, id: id, name: name, avatarHash: avatarHash.isEmpty ? null : avatarHash);
      } else if (type == MeshMessageType.pilotInfoRequest.value) {
        return MeshPilotInfoRequest(tag, nodeNum: r.u32());
      } else if (type == MeshMessageType.selectWaypoint.value) {
        final id = r.restString();
        return MeshSelectWaypoint(tag, waypointId: id.isEmpty ? null : id);
      } else if (type == MeshMessageType.waypointUpdate.value) {
        return MeshWaypointUpdate._decode(tag, r);
      }
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
    return null;
  }
}

class MeshTelemetry extends MeshMessage {
  final double lat;
  final double lng;
  final double alt;

  /// Milliseconds since epoch (sent with 1 second resolution)
  final int timestamp;

  const MeshTelemetry(super.groupTag, {required this.lat, required this.lng, required this.alt, required this.timestamp});

  @override
  MeshMessageType get type => MeshMessageType.telemetry;

  /// Position is sent with ~1-2m resolution, which is plenty for showing another pilot on the map.
  @override
  void _encodeBody(_Writer w) {
    w
      ..u24(_encodeAngle(lat, 90))
      ..u24(_encodeAngle(lng, 180))
      ..i16(alt.round().clamp(-32768, 32767))
      ..u16(timestamp ~/ 1000);
  }
}

/// Map an angle in [-range, range] onto 24 bits.
int _encodeAngle(double value, double range) => ((value + range) / (2 * range) * 0xFFFFFF).round().clamp(0, 0xFFFFFF);

double _decodeAngle(int value, double range) => value / 0xFFFFFF * 2 * range - range;

/// Timestamps are sent as the low 16 bits of seconds since epoch (~18 hours). Pick the time nearest [now].
int _expandTime(int low16, int now) {
  final nowSec = now ~/ 1000;
  var sec = (nowSec & ~0xFFFF) | low16;
  if (sec - nowSec > 0x8000) sec -= 0x10000;
  if (nowSec - sec > 0x8000) sec += 0x10000;
  return sec * 1000;
}

class MeshChat extends MeshMessage {
  /// Milliseconds since epoch (sent with 1 second resolution)
  final int timestamp;
  final bool emergency;
  final String text;

  /// Longest text that still fits in one packet, in utf8 bytes.
  static const int maxTextBytes = meshMaxPayload - _headerLen - 3;

  const MeshChat(super.groupTag, {required this.timestamp, required this.emergency, required this.text});

  @override
  MeshMessageType get type => MeshMessageType.chat;

  /// Flags: bit0 emergency, bit1 [meshQuickPhrases] index instead of text
  @override
  void _encodeBody(_Writer w) {
    final quickIndex = meshQuickPhrases.indexOf(text);
    w
      ..u16(timestamp ~/ 1000)
      ..u8((emergency ? 0x1 : 0) | (quickIndex >= 0 ? 0x2 : 0));
    if (quickIndex >= 0) {
      w.u8(quickIndex);
    } else {
      w.raw(truncateUtf8(text, maxTextBytes));
    }
  }
}

class MeshPilotInfo extends MeshMessage {
  final String id;
  final String name;
  final String? avatarHash;

  const MeshPilotInfo(super.groupTag, {required this.id, required this.name, this.avatarHash});

  @override
  MeshMessageType get type => MeshMessageType.pilotInfo;

  @override
  void _encodeBody(_Writer w) {
    w
      ..str8(id)
      ..str8(name)
      ..str8(avatarHash ?? "");
  }
}

class MeshPilotInfoRequest extends MeshMessage {
  /// Node that should announce itself. 0 asks everyone.
  final int nodeNum;

  const MeshPilotInfoRequest(super.groupTag, {required this.nodeNum});

  @override
  MeshMessageType get type => MeshMessageType.pilotInfoRequest;

  @override
  void _encodeBody(_Writer w) => w.u32(nodeNum);
}

class MeshSelectWaypoint extends MeshMessage {
  final String? waypointId;

  const MeshSelectWaypoint(super.groupTag, {required this.waypointId});

  @override
  MeshMessageType get type => MeshMessageType.selectWaypoint;

  @override
  void _encodeBody(_Writer w) => w.raw(utf8.encode(waypointId ?? ""));
}

class MeshWaypointUpdate extends MeshMessage {
  /// `WaypointAction` index
  final int action;

  /// `Waypoint.toJson()`
  final Map<String, dynamic> waypoint;

  const MeshWaypointUpdate(super.groupTag, {required this.action, required this.waypoint});

  @override
  MeshMessageType get type => MeshMessageType.waypointUpdate;

  /// Binary rather than JSON so longer paths fit. Points are delta-encoded varints at 1e-6 degrees,
  /// the same precision as `Waypoint.toJson()`, so the waypoint arrives exactly as sent.
  @override
  void _encodeBody(_Writer w) {
    w
      ..u8(action)
      ..str8(parseAsString(waypoint["id"]) ?? "");
    if (action == WaypointAction.delete.index) return;

    final String? icon = waypoint["icon"];
    final int? color = waypoint["color"];
    w
      ..str8(waypoint["name"] ?? "")
      ..u8((icon != null ? 0x1 : 0) | (color != null ? 0x2 : 0));
    if (icon != null) w.str8(icon);
    if (color != null) w.zigzag(color);

    final List points = waypoint["latlng"] ?? [];
    w.varint(points.length);
    int prevLat = 0;
    int prevLng = 0;
    for (final List point in points) {
      final lat = ((point[0] as num) * 1e6).round();
      final lng = ((point[1] as num) * 1e6).round();
      w
        ..zigzag(lat - prevLat)
        ..zigzag(lng - prevLng);
      prevLat = lat;
      prevLng = lng;
    }
  }

  static MeshWaypointUpdate _decode(int tag, _Reader r) {
    final action = r.u8();
    final id = r.str8();
    if (action == WaypointAction.delete.index) return MeshWaypointUpdate(tag, action: action, waypoint: {"id": id});

    final name = r.str8();
    final flags = r.u8();
    final icon = flags & 0x1 != 0 ? r.str8() : null;
    final color = flags & 0x2 != 0 ? r.zigzag() : null;

    final count = r.varint();
    final latlng = <List<double>>[];
    int lat = 0;
    int lng = 0;
    for (int i = 0; i < count; i++) {
      lat += r.zigzag();
      lng += r.zigzag();
      latlng.add([lat / 1e6, lng / 1e6]);
    }
    return MeshWaypointUpdate(tag,
        action: action, waypoint: {"id": id, "name": name, "latlng": latlng, "icon": icon, "color": color});
  }
}

/// Encode [text] as utf8, dropping trailing characters until it fits in [maxBytes].
Uint8List truncateUtf8(String text, int maxBytes) {
  var bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return bytes;
  final runes = text.runes.toList();
  while (bytes.length > maxBytes && runes.isNotEmpty) {
    runes.removeLast();
    bytes = utf8.encode(String.fromCharCodes(runes));
  }
  return bytes;
}

// ############################################################################
//
//     De-duplication (messages can arrive over both cellular and mesh)
//
// ############################################################################

class _SeenChat {
  final String pilotId;
  final String text;
  final int senderTimestamp;
  final int receivedAt;

  _SeenChat(this.pilotId, this.text, this.senderTimestamp, this.receivedAt);
}

class ChatDeduper {
  /// How long to remember messages
  final Duration window;

  /// Sender timestamps within this many ms are the same message. (mesh drops sub-second resolution)
  final int toleranceMs;

  final List<_SeenChat> _seen = [];

  ChatDeduper({this.window = const Duration(minutes: 5), this.toleranceMs = 2000});

  /// Records the message and returns true if it was already seen.
  bool isDuplicate(String pilotId, String text, int senderTimestamp, {required int now}) {
    _seen.removeWhere((e) => now - e.receivedAt > window.inMilliseconds);
    // Compare as the mesh would have sent it, since mesh text may have been truncated to fit the packet.
    final normalized = utf8.decode(truncateUtf8(text, MeshChat.maxTextBytes));
    for (final each in _seen) {
      if (each.pilotId == pilotId &&
          each.text == normalized &&
          (senderTimestamp - each.senderTimestamp).abs() <= toleranceMs) {
        return true;
      }
    }
    _seen.add(_SeenChat(pilotId, normalized, senderTimestamp, now));
    return false;
  }
}

/// Only lets through telemetry that is newer than what we already have for a pilot.
class TelemetryDeduper {
  final Map<String, int> _lastSecond = {};

  /// Returns true if this update is new. Compared at 1 second resolution since mesh drops milliseconds.
  bool accept(String pilotId, int timestamp) {
    final second = timestamp ~/ 1000;
    final last = _lastSecond[pilotId];
    if (last != null && second <= last) return false;
    _lastSecond[pilotId] = second;
    return true;
  }

  void clear() => _lastSecond.clear();
}

// ############################################################################
//
//     Byte helpers (big endian)
//
// ############################################################################

class _Writer {
  final BytesBuilder _b = BytesBuilder(copy: false);

  Uint8List get bytes => _b.toBytes();

  void u8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) => _b.add([(v >> 8) & 0xFF, v & 0xFF]);
  void i16(int v) => _b.add((ByteData(2)..setInt16(0, v)).buffer.asUint8List());
  void u24(int v) => _b.add([(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  void u32(int v) => _b.add((ByteData(4)..setUint32(0, v & 0xFFFFFFFF)).buffer.asUint8List());
  void raw(List<int> v) => _b.add(v);

  /// Unsigned LEB128 varint
  void varint(int v) {
    do {
      int byte = v & 0x7F;
      v = v >>> 7;
      if (v != 0) byte |= 0x80;
      _b.addByte(byte);
    } while (v != 0);
  }

  /// Signed varint, so small negative numbers stay small
  void zigzag(int v) => varint((v << 1) ^ (v >> 63));

  /// String with a 1 byte length prefix
  void str8(String v) {
    final bytes = truncateUtf8(v, 255);
    u8(bytes.length);
    raw(bytes);
  }
}

class _Reader {
  final ByteData _data;
  int _pos = 0;

  _Reader(List<int> data) : _data = ByteData.sublistView(Uint8List.fromList(data));

  int u8() => _data.getUint8(_pos++);
  int u16() {
    final v = _data.getUint16(_pos);
    _pos += 2;
    return v;
  }

  int i16() {
    final v = _data.getInt16(_pos);
    _pos += 2;
    return v;
  }

  int u24() => (u8() << 16) | u16();

  int u32() {
    final v = _data.getUint32(_pos);
    _pos += 4;
    return v;
  }

  int varint() {
    int result = 0;
    for (int shift = 0; shift < 64; shift += 7) {
      final byte = u8();
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
    }
    throw RangeError("varint too long");
  }

  int zigzag() {
    final v = varint();
    return (v >>> 1) ^ -(v & 1);
  }

  String str8() {
    final len = u8();
    if (_pos + len > _data.lengthInBytes) throw RangeError("str8 past end");
    final s = utf8.decode(_data.buffer.asUint8List(_data.offsetInBytes + _pos, len), allowMalformed: true);
    _pos += len;
    return s;
  }

  String restString() {
    final s = utf8.decode(_data.buffer.asUint8List(_data.offsetInBytes + _pos), allowMalformed: true);
    _pos = _data.lengthInBytes;
    return s;
  }
}
