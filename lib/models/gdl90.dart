import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/datadog.dart';

import 'package:xcnav/models/ga.dart';
import 'package:xcnav/units.dart';

int _decode24bit(Uint8List data) {
  int value = ((data[0] & 0x7f) << 16) | (data[1] << 8) | data[2];
  if (data[0] & 0x80 > 0) {
    value -= 0x7fffff;
  }
  return value;
}

GA? _decodeTraffic(Uint8List data) {
  final String id = String.fromCharCodes(data.sublist(18, 18 + 8)).trim().toUpperCase();

  final double lat = _decode24bit(data.sublist(4, 7)) * 180.0 / 0x7fffff;
  final double lng = _decode24bit(data.sublist(7, 10)) * 180.0 / 0x7fffff;

  final Uint8List altRaw = data.sublist(10, 12);
  final double alt = ((((altRaw[0] << 4) + (altRaw[1] >> 4)) * 25) - 1000) / meters2Feet;

  final double hdg = data[16] * 360 / 256.0;
  final double spd = ((data[13] << 4) + (data[14] >> 4)) * 0.51444;

  GAtype type = GAtype.large;
  final i = data[17];
  if (i == 1 || i == 9 || i == 10) {
    type = GAtype.small;
  } else if (i == 7) {
    type = GAtype.heli;
  } else {
    // report some other code
    error("Unknown ADSB type", attributes: {"id": id, "latlng": LatLng(lat, lng).toString(), "alt": alt, "type": i});
  }

  if (type.index > 0 && type.index < 22 && (lat != 0 || lng != 0) && (lat < 90 && lat > -90)) {
    return GA(id, LatLng(lat, lng), alt, spd, hdg, type, DateTime.now().millisecondsSinceEpoch);
  }
  return null;
}

GA? decodeGDL90(Uint8List data) {
  if (data[1] == 20) {
    // --- traffic
    return _decodeTraffic(data.sublist(2));
  }
  return null;
}
