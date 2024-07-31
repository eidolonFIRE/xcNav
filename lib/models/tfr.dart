import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/datadog.dart';
import 'package:xcnav/timezones.dart';
import 'package:xcnav/util.dart';
import 'package:xml/xml.dart';

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
      shapes.add((poly as List<dynamic>).map((e) => latlngFromJson(e)).whereNotNull().toList());
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
