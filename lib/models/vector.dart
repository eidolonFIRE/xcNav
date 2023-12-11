import 'package:xcnav/models/geo.dart';

/// Simple direction and value
class Vector {
  late final DateTime? timestamp;

  /// Radians
  late final double hdg;

  /// Meters
  late final double value;

  /// Meters
  late final double alt;
  Vector(this.hdg, this.value, {this.alt = 0, this.timestamp});

  Vector.distFromGeoToGeo(Geo a, Geo b) {
    hdg = a.relativeHdg(b);
    value = a.distanceTo(b);
    alt = a.alt - b.alt;
    timestamp = null;
  }
}
