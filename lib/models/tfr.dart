import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/timezones.dart';
import 'package:xml/xml.dart';

class TFR {
  late String notamText;
  late List<LatLng> latlngs;
  late DateTimeRange activeTime;
  late String? purpose;

  bool isActive(Duration buffer) {
    final now = DateTime.now();
    return now.isAfter(activeTime.start.subtract(buffer)) && now.isBefore(activeTime.end.add(buffer));
  }

  TFR.fromXML(XmlDocument document) {
    // --- Reference NOTAM
    notamText = document.findAllElements("txtDescrTraditional").first.text.replaceAll(". ", ". \n");

    // --- Purpose
    purpose = document.findAllElements("txtDescrPurpose").singleOrNull?.text;

    // --- Parse unified shape
    latlngs = [];
    final mergedShape = document.findAllElements("abdMergedArea").firstOrNull;
    if (mergedShape != null) {
      for (final each in mergedShape.findAllElements("Avx")) {
        final latStr = each.getElement("geoLat")!.text;
        final lat = double.parse(latStr.substring(0, latStr.length - 1));
        final lngStr = each.getElement("geoLong")!.text;
        final lng = double.parse(lngStr.substring(0, lngStr.length - 1)) * (lngStr.endsWith("W") ? -1 : 1);
        latlngs.add(LatLng(lat, lng));
      }
    } else {
      // TODO: alternate shape parsing?
    }

    // --- Parse Active time
    final zone = document.findAllElements("codeTimeZone").first.text;
    final startStr = document.findAllElements("dateEffective").firstOrNull?.text ??
        document.findAllElements("dateIssued").firstOrNull?.text;
    final endStr = document.findAllElements("dateExpire").firstOrNull?.text;
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
