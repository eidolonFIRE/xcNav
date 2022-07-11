import 'dart:typed_data';
// import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/models/ga.dart';

int _decode32bit(Uint8List data, int offset) {
  return data.buffer.asByteData().getInt32(offset, Endian.little);
}

int _decode16bit(Uint8List data, int offset) {
  return data.buffer.asByteData().getInt16(offset, Endian.little);
}

/// Accumulate the X.25 CRC by adding one char at a time.
/// The checksum function adds the hash of one char at a time to the
/// 16 bit checksum (Uint16).
/// - data - New char to hash
/// - crcAccum - Already accumulated checksum
int crcAccumulate(int data, int crcAccum) {
  int tmp = (data ^ (crcAccum & 0xff)) & 0xff;
  tmp ^= (tmp << 4);
  return ((crcAccum >> 8) ^ (tmp << 8) ^ (tmp << 3) ^ (tmp >> 4)) & 0xffff;
}

/// Accumulate the X.25 CRC by adding an array of bytes
/// The checksum function adds the hash of one char at a time to the
/// 16 bit checksum (Uint16).
/// - data - New bytes to hash
/// - crcAccum - Already accumulated checksum
int crcAccumulateBuffer(int crcAccum, Uint8List buffer, int length) {
  int index = 0xffff;
  while (index < length) {
    crcAccum = crcAccumulate(buffer[index], crcAccum);
    index++;
  }
  return crcAccum;
}

/// byte,  Field,     Type,     Description
/// 0  ICAO_address   uint32_t  ICAO Address
/// 4  lat            int32_t   The reported latitude in degrees /// 1E7
/// 8  lon            int32_t   The reported longitude in degrees /// 1E7
/// 12 altitude       int32_t   Altitude in Meters /// 1E3 (up is +ve) - Check ALT_TYPE for reference datum
/// 16 heading        Uint16  Course over ground in degrees /// 10^2
/// 18 hor_velocity   Uint16  The horizontal velocity in (m/s /// 1E2)
/// 20 ver_velocity   int16_t   The vertical velocity in (m/s /// 1E2)
/// 22 validFlags     Uint16  Valid data fields
/// 24 squawk         Uint16  Mode A Squawk code (0xFFFF = no code)
/// 26 altitude_type  Uint8   Altitude Type
/// 27 callsign       char[9]   The callsign
/// 36 emitter_type   Uint8   Emitter Category
/// 37 tslc           Uint8   Time since last communication in seconds
///
/// --- EMITTER TYPE ---
/// 0x00: NO_TYPE_INFO
/// 0x01: LIGHT_TYPE
/// 0x02: SMALL_TYPE
/// 0x03: LARGE_TYPE
/// 0x04: HIGH_VORTEX_LARGE_TYPE
/// 0x05: HEAVY_TYPE
/// 0x06: HIGHLY_MANUV_TYPE
/// 0x07: ROTOCRAFT_TYPE
/// 0x08: UNASSIGNED_TYPE
/// 0x09: GLIDER_TYPE
/// 0x0A: LIGHTER_AIR_TYPE
/// 0x0B: PARACHUTE_TYPE
/// 0x0C: ULTRA_LIGHT_TYPE
/// 0x0D: UNASSIGNED2_TYPE
/// 0x0E: UAV_TYPE
/// 0x0F: SPACE_TYPE
/// 0x10: UNASSGINED3_TYPE
/// 0x11: EMERGENCY_SURFACE_TYPE
/// 0x12: SERVICE_SURFACE_TYPE
/// 0x13: POINT_OBSTACLE_TYPE
GA? _decodeTraffic(Uint8List data) {
  final id = String.fromCharCodes(data.sublist(27, 27 + 8)).trim();
  final lat = _decode32bit(data, 4) / 1e7;
  final lng = _decode32bit(data, 8) / 1e7;
  // TODO: check altitude type
  final alt = _decode32bit(data, 12) / 1e3;
  final spd = _decode16bit(data, 18) / 1e2;
  final hdg = _decode16bit(data, 16) / 1e2;
  GAtype type = GAtype.large;
  if (data[36] == 0x07) {
    type = GAtype.heli;
  } else if (data[36] == 0x01 || data[36] == 0x02 || data[36] == 0x09 || data[36] == 0x0A || data[36] == 0x0C) {
    type = GAtype.small;
  }

  if (type.index > 0 && type.index < 22 && (lat != 0 || lng != 0) && (lat < 90 && lat > -90)) {
    return GA(id, LatLng(lat, lng), alt, spd, hdg, type, DateTime.now().millisecondsSinceEpoch);
  }
  return null;
}

// pingUSB messages

// Message ID, Description, I/O Length, CRC Extra

// OUT
// 66: DataStream Request, 6, 148
// 246: Traffic Report, 38, 184
// 203: Status, 1, 85
// 202: Ownship, 42, 7

// IN
// 202: Dynamic, 42, 7
// 202: Navigation, 51, 11
// 29: Scaled Pressure, 14, 115
// 201: Static, 19, 126
// 248: Identification, 69, 8

GA? decodeMavlink(Uint8List data) {
  if (data.length >= 6) {
    final len = data[1];
    if (data[5] == 246) {
      if (data.length >= len + 8) {
        int checkSum = data[len + 6] | (data[len + 7] << 8);
        int finalCheck = crcAccumulateBuffer(checkSum, data.sublist(1), len + 5);
        if (checkSum == finalCheck) {
          return _decodeTraffic(data.sublist(6));
        } else {
          // debugPrint("MAVLINK: invalid checksum!");
        }
      } else {
        // debugPrint("MAVLINK: massage didn't contain full payload! ${data.length} < ${len + 8}");
      }
    }
  } else {
    // debugPrint("MAVLINK: message too small for header!");
  }
  return null;
}
