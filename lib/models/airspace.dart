import 'dart:math';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/util.dart';

/// OpenAIP airspace types we don't draw. These are either huge (FIR / ADIZ) or not real boundaries for VFR.
const _ignoredTypes = {
  10, // FIR
  11, // UIR
  12, // ADIZ
  15, // Airway
  16, // Military Training Route
  17, // Alert Area (not needed for now)
  22, // Transponder Setting
  27, // ACC Sector
  30, // Military Route
  31, // TSA/TRA Feeding Route
  32, // VFR Sector
  33, // FIS Sector
};

/// Airspaces starting above this (meters MSL) are irrelevant for us. (~FL180)
const _maxRelevantFloor = 5486.0;

/// Class E is only shown when it extends to the surface. Otherwise it covers nearly everything.
const _classE = 4;

/// Simplify OpenAIP outlines to this tolerance (degrees latitude, ~10m). Some arcs come with thousands of vertices.
const _simplifyTolerance = 0.0001;

const _typeNames = {
  0: "Other",
  1: "Restricted",
  2: "Danger",
  3: "Prohibited",
  4: "CTR",
  5: "TMZ",
  6: "RMZ",
  7: "TMA",
  8: "TRA",
  9: "TSA",
  10: "FIR",
  11: "UIR",
  12: "ADIZ",
  13: "ATZ",
  14: "MATZ",
  15: "Airway",
  16: "MTR",
  17: "Alert Area",
  18: "Warning Area",
  19: "Protected Area",
  20: "HTZ",
  21: "Gliding Sector",
  22: "TRP",
  23: "TIZ",
  24: "TIA",
  25: "MTA",
  26: "CTA",
  27: "ACC Sector",
  28: "Sport/Recreation",
  29: "Low Overflight Restriction",
  30: "MRT",
  31: "TFR",
  32: "VFR Sector",
  33: "FIS Sector",
  34: "LTA",
  35: "UTA",
  36: "MCTR",
};

const _icaoClassNames = {0: "A", 1: "B", 2: "C", 3: "D", 4: "E", 5: "F", 6: "G"};

enum AltLimitUnit { meter, feet, flightLevel }

enum AltLimitDatum { gnd, msl, std }

/// Vertical limit of an airspace. (OpenAIP v2 `upperLimit` / `lowerLimit`)
class AltLimit {
  final int value;
  final AltLimitUnit unit;
  final AltLimitDatum datum;

  const AltLimit(this.value, this.unit, this.datum);

  static AltLimit? fromOpenAip(dynamic data) {
    if (data is! Map) return null;
    final value = data["value"];
    if (value is! num) return null;
    final unit =
        switch (data["unit"]) { 0 => AltLimitUnit.meter, 6 => AltLimitUnit.flightLevel, _ => AltLimitUnit.feet };
    final datum =
        switch (data["referenceDatum"]) { 0 => AltLimitDatum.gnd, 2 => AltLimitDatum.std, _ => AltLimitDatum.msl };
    return AltLimit(value.round(), unit, datum);
  }

  /// Raw value converted to meters (no datum applied)
  double get meters {
    switch (unit) {
      case AltLimitUnit.meter:
        return value.toDouble();
      case AltLimitUnit.feet:
        return value * 0.3048;
      case AltLimitUnit.flightLevel:
        return value * 30.48;
    }
  }

  /// Meters MSL. AGL limits are added to [ground]. Flight levels assume standard pressure.
  double toMsl(double ground) => meters + (datum == AltLimitDatum.gnd ? ground : 0);

  bool get isGround => value == 0 && datum == AltLimitDatum.gnd;

  @override
  String toString() {
    if (isGround) return "GND";
    if (unit == AltLimitUnit.flightLevel) return "FL$value";
    return "$value${unit == AltLimitUnit.feet ? "ft" : "m"} ${datum == AltLimitDatum.gnd ? "AGL" : "MSL"}";
  }

  Map<String, dynamic> toJson() => {"v": value, "u": unit.index, "d": datum.index};

  AltLimit.fromJson(Map<String, dynamic> data)
      : value = data["v"],
        unit = AltLimitUnit.values[data["u"]],
        datum = AltLimitDatum.values[data["d"]];
}

class Airspace {
  final String id;
  final String name;

  /// OpenAIP type enum
  final int type;

  /// OpenAIP ICAO class enum (8 = unclassified / SUA)
  final int icaoClass;

  final AltLimit lower;
  final AltLimit upper;

  final List<LatLng> points;

  late final LatLngBoundsSimple bounds = LatLngBoundsSimple.fromPoints(points);

  Airspace(
      {required this.id,
      required this.name,
      required this.type,
      required this.icaoClass,
      required this.lower,
      required this.upper,
      required this.points});

  /// Parse an item from the OpenAIP v2 core API (`/api/airspaces`). Returns null if unusable.
  static Airspace? fromOpenAip(Map<String, dynamic> data) {
    final geometry = data["geometry"];
    if (geometry is! Map || geometry["type"] != "Polygon") return null;
    final rings = geometry["coordinates"];
    if (rings is! List || rings.isEmpty || rings.first is! List) return null;
    final points = <LatLng>[];
    for (final each in rings.first as List) {
      if (each is List && each.length >= 2 && each[0] is num && each[1] is num) {
        points.add(LatLng((each[1] as num).toDouble(), (each[0] as num).toDouble()));
      }
    }
    // Ring is closed, so drop the repeated last point
    if (points.length > 1 && points.first == points.last) points.removeLast();
    if (points.length < 3) return null;
    final simplified = simplifyRing(points, _simplifyTolerance);

    final lower = AltLimit.fromOpenAip(data["lowerLimit"]);
    final upper = AltLimit.fromOpenAip(data["upperLimit"]);
    if (lower == null || upper == null) return null;

    return Airspace(
        id: data["_id"]?.toString() ?? "",
        name: data["name"]?.toString() ?? "",
        type: data["type"] is int ? data["type"] : 0,
        icaoClass: data["icaoClass"] is int ? data["icaoClass"] : 8,
        lower: lower,
        upper: upper,
        points: simplified.length >= 3 ? simplified : points);
  }

  /// Whether this airspace is worth showing to a low flying pilot
  bool get isRelevant =>
      !_ignoredTypes.contains(type) && lower.meters < _maxRelevantFloor && (icaoClass != _classE || lower.isGround);

  String get typeName => _typeNames[type] ?? "Other";

  String? get icaoClassName => _icaoClassNames[icaoClass];

  /// Short label like "Class C" or "Restricted"
  String get label {
    // For controlled airspace, the class says the most.
    if (icaoClassName != null && const {0, 4, 7, 13, 26}.contains(type)) return "Class $icaoClassName";
    return typeName + (icaoClassName != null ? " ($icaoClassName)" : "");
  }

  /// Colors loosely follow the FAA sectional chart style.
  Color get color {
    switch (type) {
      case 1: // restricted
      case 3: // prohibited
      case 29: // low overflight restriction
        return Colors.red;
      case 2: // danger
      case 18: // warning
      case 25: // MTA
      case 8: // TRA
      case 9: // TSA
        return Colors.orange.shade800;
      case 5: // TMZ
      case 6: // RMZ
        return Colors.purple;
      case 21: // gliding
      case 28: // sport
        return Colors.green.shade700;
    }
    switch (icaoClass) {
      case 0: // A
        return Colors.grey.shade700;
      case 1: // B
      case 3: // D
        return Colors.blue.shade800;
      case 2: // C
      case 4: // E
        return Colors.pink.shade400;
      default:
        return Colors.blueGrey;
    }
  }

  /// Draw dashed outline (class D / E as on sectionals)
  bool get dashed => icaoClass == 3 || icaoClass == 4;

  bool containsPoint(LatLng point) => bounds.contains(point) && polygonContainsPoint(point, points);

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "type": type,
        "icaoClass": icaoClass,
        "lower": lower.toJson(),
        "upper": upper.toJson(),
        // compact: [lat, lng, lat, lng, ...]
        "points": points.expand((e) => [e.latitude, e.longitude]).toList(),
      };

  static Airspace fromJson(Map<String, dynamic> data) {
    final flat = (data["points"] as List).map((e) => (e as num).toDouble()).toList();
    return Airspace(
        id: data["id"],
        name: data["name"],
        type: data["type"],
        icaoClass: data["icaoClass"],
        lower: AltLimit.fromJson(data["lower"]),
        upper: AltLimit.fromJson(data["upper"]),
        points: List.generate(flat.length ~/ 2, (i) => LatLng(flat[i * 2], flat[i * 2 + 1])));
  }
}

/// Ramer-Douglas-Peucker on a polygon ring. [tolerance] is in degrees latitude.
List<LatLng> simplifyRing(List<LatLng> points, double tolerance) {
  if (points.length < 4) return points;
  final lngScale = cos(points.first.latitude * pi / 180);
  final keep = List.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;

  double distToSegment(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude * lngScale, ay = a.latitude;
    final dx = b.longitude * lngScale - ax, dy = b.latitude - ay;
    final px = p.longitude * lngScale - ax, py = p.latitude - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : ((px * dx + py * dy) / len2).clamp(0.0, 1.0);
    final ex = px - t * dx, ey = py - t * dy;
    return sqrt(ex * ex + ey * ey);
  }

  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (start, end) = stack.removeLast();
    double maxDist = 0;
    int index = start;
    for (int i = start + 1; i < end; i++) {
      final d = distToSegment(points[i], points[start], points[end]);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }
    if (maxDist > tolerance) {
      keep[index] = true;
      stack.add((start, index));
      stack.add((index, end));
    }
  }
  return [
    for (int i = 0; i < points.length; i++)
      if (keep[i]) points[i]
  ];
}

/// Cheap bounding box for quick rejection before point-in-polygon tests.
class LatLngBoundsSimple {
  final double north, south, east, west;

  const LatLngBoundsSimple(this.north, this.south, this.east, this.west);

  factory LatLngBoundsSimple.fromPoints(Iterable<LatLng> points) {
    double n = -90, s = 90, e = -180, w = 180;
    for (final p in points) {
      n = max(n, p.latitude);
      s = min(s, p.latitude);
      e = max(e, p.longitude);
      w = min(w, p.longitude);
    }
    return LatLngBoundsSimple(n, s, e, w);
  }

  /// Box around a circle of [radius] meters
  factory LatLngBoundsSimple.around(LatLng center, double radius) {
    final dLat = radius / 111320;
    final dLng = dLat / max(0.01, cos(center.latitude * pi / 180));
    return LatLngBoundsSimple(min(90, center.latitude + dLat), max(-90, center.latitude - dLat),
        min(180, center.longitude + dLng), max(-180, center.longitude - dLng));
  }

  bool contains(LatLng p) => p.latitude >= south && p.latitude <= north && p.longitude >= west && p.longitude <= east;

  bool overlaps(LatLngBoundsSimple o) => !(o.west > east || o.east < west || o.south > north || o.north < south);
}

/// A point along the elevation plot's horizontal axis to test for airspace.
class AirspaceProbe {
  /// Plot x value
  final double x;
  final LatLng latlng;

  /// Ground elevation (meters MSL) used for AGL limits
  final double ground;

  const AirspaceProbe(this.x, this.latlng, this.ground);
}

/// Continuous span of one airspace along the probes. Each point is (x, bottom, top) in meters MSL.
class AirspaceSection {
  final Airspace airspace;
  final List<({double x, double bottom, double top})> points;

  const AirspaceSection(this.airspace, this.points);
}

/// Vertical cross section of [airspaces] along consecutive [probes].
List<AirspaceSection> airspaceCrossSection(List<AirspaceProbe> probes, Iterable<Airspace> airspaces) {
  if (probes.isEmpty) return [];
  final probeBounds = LatLngBoundsSimple.fromPoints(probes.map((e) => e.latlng));

  final List<AirspaceSection> sections = [];
  for (final airspace in airspaces) {
    if (!airspace.bounds.overlaps(probeBounds)) continue;
    List<({double x, double bottom, double top})>? run;
    for (final probe in probes) {
      if (airspace.containsPoint(probe.latlng)) {
        run ??= [];
        final bottom = airspace.lower.toMsl(probe.ground);
        final top = airspace.upper.toMsl(probe.ground);
        if (top > bottom) run.add((x: probe.x, bottom: bottom, top: top));
      } else if (run != null) {
        if (run.isNotEmpty) sections.add(AirspaceSection(airspace, run));
        run = null;
      }
    }
    if (run != null && run.isNotEmpty) sections.add(AirspaceSection(airspace, run));
  }
  return sections;
}
