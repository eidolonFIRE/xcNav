import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/util.dart';

enum GAtype {
  unknown,
  small,
  large,
  heli,
}

Map<GAtype, String> gaTypeStr = {
  GAtype.unknown: "unknown",
  GAtype.small: "small airplane",
  GAtype.large: "large airplane",
  GAtype.heli: "helicopter",
};

double getGAtransparency(double relativeAlt) {
  const verticalClose = 300;
  const verticalFade = 800;
  const minTransparency = 0.3;
  return max(minTransparency,
      min(1.0, (1.0 - max(0, relativeAlt.abs() - verticalClose) * ((1.0 - minTransparency) / verticalFade))));
}

class GA {
  final String id;
  final LatLng latlng;

  /// Meters
  final double alt;

  /// m/s
  final double spd;

  /// Degrees
  final double hdg;
  final int timestamp;
  final GAtype type;

  bool warning = false;

  /// Get the GA craft's dynamic icon.
  /// - Full opacity within close vertical range or has warning
  /// - Fade transparency with vertical separation
  /// - Red Icon when on warning & close vertical range.
  SvgPicture getIcon() {
    Color color = warning ? Colors.red : Colors.amber.shade600;

    switch (type) {
      case GAtype.small:
        return SvgPicture.asset("assets/images/ga_small.svg", colorFilter: ColorFilter.mode(color, BlendMode.srcIn));
      case GAtype.heli:
        return SvgPicture.asset("assets/images/ga_heli.svg", colorFilter: ColorFilter.mode(color, BlendMode.srcIn));
      default:
        return SvgPicture.asset("assets/images/ga_large.svg", colorFilter: ColorFilter.mode(color, BlendMode.srcIn));
    }
  }

  GA(this.id, this.latlng, this.alt, this.spd, this.hdg, this.type, this.timestamp) {
    // debugPrint("GA $id (${gaTypeStr[type]}): $latlng, $spd m/s  $alt m, $hdg deg");
    debugPrint("GA \"$id\" $latlng, $spd m/s  $alt m, $hdg deg");
  }

  /// Server "Airplane" format
  Map<String, dynamic> toJson() => {
        "id": id,
        "latlng": [latlng.latitude, latlng.longitude],
        "alt": alt,
        "spd": spd,
        "hdg": hdg,
        "timestamp": timestamp,
        "type": type.index,
      };

  /// Parse server "Airplane" format. Null if malformed.
  static GA? fromJson(dynamic data) {
    if (data is! Map) return null;
    final id = parseAsString(data["id"]);
    final latlng = data["latlng"];
    if (id == null || id.isEmpty || latlng is! List || latlng.length < 2) return null;
    final lat = parseAsDouble(latlng[0]);
    final lng = parseAsDouble(latlng[1]);
    final alt = parseAsDouble(data["alt"]);
    final timestamp = parseAsInt(data["timestamp"]);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180 || alt == null || timestamp == null) {
      return null;
    }
    final typeIndex = parseAsInt(data["type"]) ?? 0;
    return GA(
        id,
        LatLng(lat, lng),
        alt,
        parseAsDouble(data["spd"]) ?? 0,
        parseAsDouble(data["hdg"]) ?? 0,
        (typeIndex >= 0 && typeIndex < GAtype.values.length) ? GAtype.values[typeIndex] : GAtype.unknown,
        timestamp);
  }
}
