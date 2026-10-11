import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/datadog.dart';
import 'package:xcnav/timezones.dart';
import 'package:xcnav/util.dart';
import 'package:xml/xml.dart';

/// Coordinates in NOTAM text such as `473249N1221904W` (DDMMSS / DDDMMSS, optional decimal seconds).
const _coordPattern = r"\d{6}(?:\.\d+)?[NS]\d{7}(?:\.\d+)?[EW]";
final _coordExpr = RegExp(r"(\d{2})(\d{2})(\d{2}(?:\.\d+)?)([NS])(\d{3})(\d{2})(\d{2}(?:\.\d+)?)([EW])");

/// e.g. `WI AN AREA DEFINED AS 4NM RADIUS OF 473249N1221904W`
final _radiusExpr = RegExp("(\\d+(?:\\.\\d+)?)\\s*(?:NM|NAUTICAL MILES?)\\s+RADIUS\\s+OF\\s+($_coordPattern)");

/// e.g. `WI AN AREA DEFINED AS 473249N1221904W (SEA338006.7) TO 473700N1221356W TO ... TO POINT OF ORIGIN`
final _polygonExpr = RegExp("$_coordPattern(?:\\s*(?:\\([^)]*\\)\\s*)?TO\\s+$_coordPattern)+");

/// Well-known airspace that NOTAMs reference by name without giving coordinates.
final _knownAirspace = <RegExp, List<List<LatLng>>>{
  // Washington DC SFRA - 14 CFR 93.335: 30nm radius of the DCA VOR/DME (385134N0770211W)
  RegExp(r"WASHINGTON,? DC SPECIAL FLIGHT RULES AREA|DC SFRA"): [_circle(const LatLng(38.85944, -77.03639), 30)],
};

LatLng? _parseCoord(String text) {
  final m = _coordExpr.firstMatch(text);
  if (m == null) return null;
  double dms(int i) =>
      double.parse(m.group(i)!) + double.parse(m.group(i + 1)!) / 60 + double.parse(m.group(i + 2)!) / 3600;
  final lat = dms(1) * (m.group(4) == "S" ? -1 : 1);
  final lng = dms(5) * (m.group(8) == "W" ? -1 : 1);
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  return LatLng(lat, lng);
}

List<LatLng> _circle(LatLng center, double radiusNm, {int segments = 36}) {
  return List.generate(segments, (i) => latlngCalc.offset(center, radiusNm * 1852, i * 360 / segments));
}

/// Best effort to pull TFR shapes out of the NOTAM free text.
List<List<LatLng>> parseShapesFromText(String text) {
  final List<List<LatLng>> shapes = [];
  final normalized = text.toUpperCase().replaceAll(RegExp(r"\s+"), " ");

  for (final m in _radiusExpr.allMatches(normalized)) {
    final center = _parseCoord(m.group(2)!);
    if (center != null) shapes.add(_circle(center, double.parse(m.group(1)!)));
  }

  for (final m in _polygonExpr.allMatches(normalized)) {
    final points = _coordExpr.allMatches(m.group(0)!).map((e) => _parseCoord(e.group(0)!)).nonNulls.toList();
    if (points.length >= 3) shapes.add(points);
  }

  if (shapes.isEmpty) {
    for (final entry in _knownAirspace.entries) {
      if (entry.key.hasMatch(normalized)) shapes.addAll(entry.value);
    }
  }

  // Remove duplicates (multi-part NOTAMs often repeat the same area)
  final seen = <String>{};
  return shapes.where((e) => seen.add(e.map((p) => "${p.latitude},${p.longitude}").join(";"))).toList();
}

class TFR {
  late String notamText;
  late List<List<LatLng>> shapes;
  late DateTimeRange activeTime;
  late String? purpose;

  bool isActive(Duration buffer) {
    final now = DateTime.now();
    return now.isAfter(activeTime.start.subtract(buffer)) && now.isBefore(activeTime.end.add(buffer));
  }

  bool containsPoint(LatLng point) {
    for (final shape in shapes) {
      if (polygonContainsPoint(point, shape)) {
        return true;
      }
    }
    return false;
  }

  void showInfoDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("TFR info"),
              content: Scrollbar(
                thumbVisibility: true,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width - 40,
                  height: MediaQuery.of(context).size.width - 100,
                  child: ListView(shrinkWrap: true, children: [
                    Text(
                      notamText,
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  ]),
                ),
              ),
            ));
  }

  Map<String, dynamic> toJson() {
    return {
      "notamText": notamText,
      "shapes": shapes.map((e) => e.map((f) => latlngToJson(f)).toList()).toList(),
      "activeTime.start": activeTime.start.millisecondsSinceEpoch,
      "activeTime.end": activeTime.end.millisecondsSinceEpoch,
      "purpose": purpose,
    };
  }

  TFR.fromJson(Map<String, dynamic> data) {
    notamText = data["notamText"];
    activeTime = DateTimeRange(
        start: DateTime.fromMillisecondsSinceEpoch(data["activeTime.start"]),
        end: DateTime.fromMillisecondsSinceEpoch(data["activeTime.end"]));
    purpose = data["purpose"];
    shapes = [];
    for (final poly in data["shapes"]) {
      shapes.add((poly as List<dynamic>).map((e) => latlngFromJson(e)).nonNulls.toList());
    }
  }

  TFR.fromXML(XmlDocument document) {
    // --- Reference NOTAM
    notamText =
        document.findAllElements("txtDescrTraditional").firstOrNull?.innerText.replaceAll(". ", ". \n") ?? "error";

    // --- Purpose
    purpose = document.findAllElements("txtDescrPurpose").singleOrNull?.innerText;

    // --- Parse unified shape
    shapes = [];
    for (final mergedShape in document.findAllElements("abdMergedArea")) {
      final List<LatLng> latlngs = [];
      for (final each in mergedShape.findAllElements("Avx")) {
        final latStr = each.getElement("geoLat")!.innerText;
        final lat = double.parse(latStr.substring(0, latStr.length - 1));
        final lngStr = each.getElement("geoLong")!.innerText;
        final lng = double.parse(lngStr.substring(0, lngStr.length - 1)) * ((lngStr.endsWith("W")) ? -1 : 1);
        if (lat != 0 && lng != 0) {
          latlngs.add(LatLng(lat, lng));
        } else {
          error("TFR shape can't be zero.", attributes: {"raw text": notamText});
        }
      }
      if (latlngs.isNotEmpty) shapes.add(latlngs);
    }

    if (shapes.isEmpty) {
      // Fallback: some TFRs (ex: Washington DC SFRA) only define the area in the NOTAM text.
      final fullText = document.findAllElements("txtDescrUSNS").firstOrNull?.innerText;
      for (final text in [fullText, notamText].nonNulls) {
        shapes = parseShapesFromText(text);
        if (shapes.isNotEmpty) break;
      }
      // The traditional text is often truncated for these, so show the full text instead.
      if (fullText != null && fullText.length > notamText.length) {
        notamText = fullText.replaceAll(". ", ". \n");
      }
    }

    if (shapes.isEmpty) {
      error("No TFR shape found.", attributes: {"raw text": notamText});
    }

    // --- Parse Active time
    final zone = document.findAllElements("codeTimeZone").first.innerText;
    final startStr = document.findAllElements("dateEffective").firstOrNull?.innerText ??
        document.findAllElements("dateIssued").firstOrNull?.innerText;
    final endStr = document.findAllElements("dateExpire").firstOrNull?.innerText;
    final curOffset = DateTime.now().timeZoneOffset;
    final start = startStr != null
        ? DateTime.parse(startStr).add(curOffset).subtract(timezones[zone]!.offset)
        // fallback time (sometimes long-standing TFR don't have a start time)
        : DateTime.now().subtract(const Duration(days: 1));
    final end = endStr != null
        ? DateTime.parse(endStr).add(curOffset).subtract(timezones[zone]!.offset)
        // fallback time (often used for permanent TFR)
        : DateTime.now().add(const Duration(days: 365));

    activeTime = DateTimeRange(start: start, end: end);
  }
}
