// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'package:xcnav/datadog.dart';
import 'package:xcnav/models/tfr.dart';
import 'package:xcnav/state_centroids.dart';
import 'package:xcnav/util.dart';

final _notamIdExpr = RegExp(r"(\d/[\d]{4})");
final dateFormat = DateFormat("mm/dd/yyyy");

List<TFR>? _loadedTFRs;
DateTime? _loadedTFRsTime;
DateTime? _lastFetched;

/// Get TFRs, if not already loaded, fetch from online resource.
Future<List<TFR>?> getTFRs(LatLng center) async {
  if (_loadedTFRsTime == null || _loadedTFRsTime!.isBefore(clock.now().subtract(const Duration(hours: 2)))) {
    // check cache
    final cached = await getCachedTFRs();

    if (cached != null && _loadedTFRs == null) {
      _loadedTFRs = cached;
      debugPrint("Loaded ${_loadedTFRs?.length} TFRs from cache.");
      _loadedTFRsTime = clock.now();
    } else {
      // try fetch
      final fetched = (await _fetchTfrs(center))?.whereNotNull().toList();
      if (fetched != null) {
        _loadedTFRs = fetched;
        debugPrint("Fetched ${_loadedTFRs?.length} TFRs.");
        _loadedTFRsTime = clock.now();
        saveTFRsCache(fetched);
      }
    }
  }
  return _loadedTFRs;
}

/// Best effort to return currently loaded TFRs synchronously.
List<TFR>? getLoadedTFRs() {
  return _loadedTFRs;
}

Future<List<TFR>?> getCachedTFRs() async {
  final prefs = await SharedPreferences.getInstance();
  if (DateTime.fromMillisecondsSinceEpoch(prefs.getInt("tfr_cache.time") ?? clock.now().millisecondsSinceEpoch)
      .isBefore(clock.now().subtract(const Duration(hours: 10)))) {
    try {
      final data = prefs.getStringList("tfr_cache.data");
      if (data != null) {
        List<TFR> tfrs = [];
        for (final each in data) {
          final parsed = jsonDecode(each);
          tfrs.add(TFR.fromJson(parsed));
        }
        return tfrs;
      } else {
        // no data
        return null;
      }
    } catch (err, trace) {
      error("Couldn't load TFR cache", errorMessage: err.toString(), errorStackTrace: trace);
      return null;
    }
  } else {
    // data no longer valid
    return null;
  }
}

void saveTFRsCache(List<TFR>? data) async {
  if (data != null && data.isNotEmpty) {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt("tfr_cache.time", clock.now().millisecondsSinceEpoch);
    prefs.setStringList("tfr_cache.data", data.map((e) => jsonEncode(e.toJson())).toList());
  }
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
Future<List<TFR?>?> _fetchTfrs(LatLng center) async {
  if (_lastFetched != null && (_lastFetched?.isAfter(clock.now().subtract(const Duration(minutes: 10))) ?? true)) {
    // Fetching too soon since last request.
    return null;
  }
  _lastFetched = clock.now();

  final listResponse = await http.get(Uri.parse('https://tfr.faa.gov/tfr2/list.jsp'));

  if (listResponse.statusCode != 200) {
    debugPrint("Couldn't get TFRs from online resource.");
    return null;
  }

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
            warn(msg,
                errorMessage: err.toString(), errorStackTrace: trace, attributes: {"notamUri": tfrUri.toString()});
          }
        } else {
          warn("Couldn't parse TFR uri", attributes: {"notamId": notamID});
        }
      }
      completer.complete(null);
    }
  });
  return await Future.wait<TFR?>(completers.map((e) => e.future).toList());
}
