import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';

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
}
