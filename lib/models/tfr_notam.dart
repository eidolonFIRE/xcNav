// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:latlong2/latlong.dart';

// final dateFormat = DateFormat("mm/dd/yyyy");
const _latlngExprRaw = r"[\d]{6}N/?[\d]{6,7}W";
final _latlngExpr = RegExp(r"([\d]{6})N(?:/)?([\d]{6,7})W");

final _reasonsExprs = [
  RegExp(r"(THIS NOTICE WILL REPLACE .*?\.)"),
  RegExp(r"(TO PROVIDE .*?\.)"),
  RegExp(r"(DUE TO .*?\.)"),
  RegExp(r"(NTL DEFENSE)")
];

/// AREA DEFINED AS 5NM RADIUS OF 310152N0951758W
final _areaSimpleExpr = RegExp(r"AREA DEFINED AS ([\d]+)NM RADIUS OF (" +
    _latlngExprRaw +
    r") (?:\([A-Z]+[0-9\.]+\) )?(SFC-[\d]+FT(?:\s)?(AGL|MSL)?)?");

/// WITHIN 30NM OF 385134N/0770211W
final _areaSimpleExpr2 = RegExp(r"WITHIN ([\d]+)NM OF (" + _latlngExprRaw + r")");

final _areaAltitudeExprs = [
  // FROM THE SURFACE UP TO BUT NOT INCLUDING FL180
  RegExp(r"(FROM( THE)? SURFACE UP TO( BUT NOT)? INCLUDING (FL[\d]+|[\d]+FT(?:\s)?(AGL|MSL)))"),
  RegExp(r"(SFC-[\d]+FT(?:\s)?(AGL|MSL)?)")
];

/// AREA DEFINED AS 340745N1191224W (CMA213007.5) TO 341022N1190927W (CMA218003.9) TO 341035N1190354W 2308180300-2308180600
final _areaArrayStartExpr = RegExp(r"AREA DEFINED AS (" + _latlngExprRaw + ")");
final _areaArrayToPointExpr = RegExp(r"TO (" + _latlngExprRaw + ")");

/// THEN CLOCKWISE ON A 4.3 NM ARC CENTERED ON 340709N1190710W
final _areaArrayArcExpr = RegExp(
    r"THEN (CLOCKWISE|COUNTERCLOCKWISE) ON A ([\d\.]+)(?:\s)?NM ARC CENTERED (?:AT|ON) (" + _latlngExprRaw + ")");
final _areaArrayStopExpr = RegExp(r"(TO (THE )?POINT OF ORIGIN)");

////////////////////////////////////////////////////////////////////////////////////

String _printLatlng(LatLng latlng) {
  return "${latlng.latitude}N/${latlng.longitude}W";
}

/// Parse a latlng out of NOTAM.
LatLng _parseLatLng(String value) {
  final match = _latlngExpr.firstMatch(value);
  return LatLng(double.parse(match!.group(1)!) / 10000, double.parse(match.group(2)!) / 10000);
}

String? _findReason(String notam) {
  for (final each in _reasonsExprs) {
    final match = each.firstMatch(notam);
    if (match != null) return match.group(1);
  }
  return null;
}

/// Parse all areas from the notam
List<TFRarea> _parseAreas(String notam) {
  List<TFRarea> retval = [];

  // --- Simple
  for (final each in _areaSimpleExpr.allMatches(notam)) {
    final area = TFRarea(radius: double.parse(each.group(1)!) * 1852, center: _parseLatLng(each.group(2)!));
    if (each.groupCount == 4) {
      area.altitude = each.group(3);
    } else {
      // look elsewhere for altitude
      for (final altExpr in _areaAltitudeExprs) {
        final match = altExpr.firstMatch(notam);
        if (match != null) {
          area.altitude = match.group(1);
        }
      }
    }

    retval.add(area);
  }

  // --- Simple alt
  for (final each in _areaSimpleExpr2.allMatches(notam)) {
    final area = TFRarea(radius: double.parse(each.group(1)!) * 1852, center: _parseLatLng(each.group(2)!));

    if (each.groupCount == 4) {
      area.altitude = each.group(3);
    } else {
      // look elsewhere for altitude
      for (final altExpr in _areaAltitudeExprs) {
        final match = altExpr.firstMatch(notam);
        if (match != null) {
          area.altitude = match.group(1);
        }
      }
    }

    retval.add(area);
  }

  // --- Polygon
  final starts = _areaArrayStartExpr.allMatches(notam).toList();
  final mids = _areaArrayToPointExpr.allMatches(notam).toList();
  final arcs = _areaArrayArcExpr.allMatches(notam).toList();
  final stops = _areaArrayStopExpr.allMatches(notam).toList();

  assert(starts.length == stops.length);

  for (final eachStart in starts.asMap().entries) {
    List<TFRareaComp> geoms = [];
    String? altitude;
    geoms.add(
        TFRareaComp(center: _parseLatLng(eachStart.value.group(1)!), parseIndex: eachStart.value.start, ccw: false));

    // mid points
    for (final eachMid in mids.where((e) => e.start > eachStart.value.start && e.start < stops[eachStart.key].start)) {
      geoms.add(TFRareaComp(center: _parseLatLng(eachMid.group(1)!), parseIndex: eachMid.start, ccw: false));
    }

    // mid arcs
    for (final eachMidArc
        in arcs.where((e) => e.start > eachStart.value.start && e.start < stops[eachStart.key].start)) {
      geoms.add(TFRareaComp(
          center: _parseLatLng(eachMidArc.group(3)!),
          isArc: true,
          parseIndex: eachMidArc.start,
          ccw: eachMidArc.group(1) == "COUNTERCLOCKWISE"));
    }

    // altitude
    for (final altExpr in _areaAltitudeExprs) {
      final match = altExpr.firstMatch(notam);
      if (match != null) {
        altitude = match.group(1);
      }
    }
    if (geoms.isNotEmpty) {
      // sort the geoms (assuming order listed in notam)
      geoms.sort((a, b) => a.parseIndex - b.parseIndex);

      retval.add(TFRarea(geom: geoms, altitude: altitude));
    }
  }

  return retval;
}

//////////////////////////////////////////////////////////////////////////////////////////////////

class TFRareaComp {
  LatLng center;
  bool isArc;

  /// Counter clockwise
  bool ccw;
  int parseIndex;
  TFRareaComp({required this.center, this.isArc = false, required this.parseIndex, required this.ccw});
}

class TFRarea {
  String? altitude;
  LatLng? center;

  /// Meters
  double? radius;

  List<TFRareaComp>? geom;

  TFRarea({this.center, this.radius, this.geom, this.altitude});

  bool isGood() {
    return (center != null && radius != null) || (geom?.isNotEmpty ?? false);
  }

  @override
  String toString() {
    if (center != null) return " - Radius: $radius from ${_printLatlng(center!)}  $altitude";
    if (geom != null) {
      return " - Polygon: ${geom!.map((e) => _printLatlng(e.center) + (e.isArc ? " (arc ${e.ccw ? "ccw" : ''})" : "")).join(', ')}  $altitude";
    }
    return "";
  }
}

class TFR {
  String? reason;
  late List<TFRarea> areas;

  TFR.fromNOTAM(String notam) {
    reason = _findReason(notam);
    areas = _parseAreas(notam);
  }

  bool isGood() {
    return reason != null && areas.isNotEmpty;
  }

  @override
  String toString() {
    return "TFR:\n - Reason: $reason\n${areas.join("\n")}\n";
  }
}
