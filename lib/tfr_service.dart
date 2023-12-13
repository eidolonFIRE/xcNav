// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/models/tfr.dart';
import 'package:xcnav/state_centroids.dart';
import 'package:xcnav/util.dart';
import 'package:xml/xml.dart';

final _notamIdExpr = RegExp(r"(\d/[\d]{4})");
final dateFormat = DateFormat("mm/dd/yyyy");

List<TFR>? _loadedTFRs;
DateTime? _loadedTFRsTime;

Future<List<TFR>?> getTFRs(LatLng center) async {
  if (_loadedTFRsTime == null || _loadedTFRsTime!.isBefore(DateTime.now().subtract(const Duration(hours: 1)))) {
    _loadedTFRsTime = DateTime.now();
    _loadedTFRs = (await _fetchTfrs(center)).whereNotNull().toList();

    debugPrint("Loaded ${_loadedTFRs?.length} TFRs.");
  }
  return _loadedTFRs;
}

/// Helper to DateFormat
extension DateFormatTryParse on DateFormat {
  DateTime? tryParse(String inputString, [bool utc = false]) {
    try {
      return parse(inputString, utc);
    } on FormatException {
      return null;
    }
  }
}

/// List all TFRs available on https://tfr.faa.gov
Future<List<TFR?>> _fetchTfrs(LatLng center) async {
  final listResponse = await http.get(Uri.parse('https://tfr.faa.gov/tfr2/list.jsp'));

  final document = parser.parse(listResponse.body);

  List<Completer<TFR?>> completers = [];

  document.getElementsByTagName("tr").forEach((element) async {
    // print(element.getElementsByTagName("a").map((e) => e.text).join(",").toString());
    final row = element.getElementsByTagName("a").toList();

    if (row.length > 2 && dateFormat.tryParse(row[0].text) != null) {
      final completer = Completer<TFR?>();
      completers.add(completer);
      // Found tfr row
      final notamID = _notamIdExpr.firstMatch(row[1].text)!.group(1)!.replaceAll("/", "_");
      final stateCode = row[3].text;
      if (stateCode != "USA" && latlngCalc.distance(center, stateCentroids[stateCode]!) < 600 * 1609.344) {
        // https://tfr.faa.gov/save_pages/detail_3_3397.xml
        final tfrUri = Uri.tryParse("https://tfr.faa.gov/save_pages/detail_$notamID.xml");
        if (tfrUri != null) {
          // Found tfr page
          final tfrDocument = XmlDocument.parse((await http.get(tfrUri)).body);
          try {
            final tfr = TFR.fromXML(tfrDocument);
            completer.complete(tfr);
            return;
          } catch (err, trace) {
            final msg = "Couldn't parse TFR: ${tfrUri.toString()}";
            DatadogSdk.instance.logs?.warn(msg,
                errorMessage: err.toString(), errorStackTrace: trace, attributes: {"notamUri": tfrUri.toString()});
          }
        } else {
          DatadogSdk.instance.logs?.warn("Couldn't parse TFR uri", attributes: {"notamId": notamID});
        }
      }
      completer.complete(null);
    }
  });

  return await Future.wait<TFR?>(completers.map((e) => e.future).toList());
}
