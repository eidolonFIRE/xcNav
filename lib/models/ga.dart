import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/models/geo.dart';

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

class GA {
  final int id;
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
  SvgPicture getIcon(Geo relative) {
    const verticalClose = 400;
    const verticalFade = 800;
    const minTransparency = 100;

    Color color = warning
        ? Colors.red
        : Colors.amber.shade600.withAlpha(max(
            minTransparency,
            min(
                255,
                (255 - max(0, (relative.alt - alt).abs() - verticalClose) * ((255 - minTransparency) / verticalFade))
                    .round())));

    switch (type) {
      case GAtype.small:
        return SvgPicture.asset("assets/images/ga_small.svg", color: color);
      case GAtype.heli:
        return SvgPicture.asset("assets/images/ga_heli.svg", color: color);
      default:
        return SvgPicture.asset("assets/images/ga_large.svg", color: color);
    }
  }

  GA(this.id, this.latlng, this.alt, this.spd, this.hdg, this.type, this.timestamp);
}
