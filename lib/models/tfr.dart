import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/timezones.dart';
import 'package:xml/xml.dart';

class TFR {
  late String notamText;
  late List<LatLng> latlngs;
  late DateTimeRange activeTime;

  TFR.fromXML(XmlDocument document) {
    // --- Reference NOTAM
    notamText = document.findAllElements("txtDescrTraditional").first.text.replaceAll(". ", ". \n");

    // --- Parse unified shape
    latlngs = [];
    final mergedShape = document.findAllElements("abdMergedArea").first;
    for (final each in mergedShape.findAllElements("Avx")) {
      final latStr = each.getElement("geoLat")!.text;
      final lat = double.parse(latStr.substring(0, latStr.length - 1));
      final lngStr = each.getElement("geoLong")!.text;
      final lng = double.parse(lngStr.substring(0, lngStr.length - 1)) * (lngStr.endsWith("W") ? -1 : 1);
      latlngs.add(LatLng(lat, lng));
    }

    // --- Parse Active time
    final zone = document.findAllElements("codeTimeZone").first.text;
    final startStr = document.findAllElements("dateEffective").first.text;
    final endStr = document.findAllElements("dateExpire").first.text;
    final curOffset = DateTime.now().timeZoneOffset;
    final start = DateTime.parse(startStr).add(curOffset).subtract(timezones[zone]!.offset);
    final end = DateTime.parse(endStr).add(curOffset).subtract(timezones[zone]!.offset);

    activeTime = DateTimeRange(start: start, end: end);
  }
}
