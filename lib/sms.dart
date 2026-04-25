import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/datadog.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/secrets.dart';
import 'package:xcnav/util.dart';
import 'package:http/http.dart' as http;

void _sendSMS(List<String> addresses, String message) async {
  try {
    // Strip off names from addresses
    List<String> recipients = addresses.map((e) => e.contains(",") ? "+${e.split(",")[1]}" : "+$e").toList();
    recipients = recipients.map((e) => e.replaceAll(r'[\(\)\-]*', "")).toList();
    if ("x$smsNotifyUrl" == "xunset") {
      debugPrint("Error while pushing avatar: secrets.dart smsNotifyUrl is unset, ignoring");
      return;
    }
    final result = await http.post(Uri.parse("https://$smsNotifyUrl"),
        headers: {"Content-Type": "application/json", "authorizationToken": smsNotifyToken},
        body: jsonEncode({"message": message, "phoneNumbers": recipients}));

    debugPrint(result.body.toString());
  } catch (err, trace) {
    final msg = "Failed to send SMS to $addresses : $message";
    error(msg, errorMessage: err.toString(), errorStackTrace: trace);
  }
}

void smsSendNotification(
    {required List<String> addresses,
    required String template,
    required LatLng latlng,
    String? pilotName,
    List<Waypoint>? waypoints}) {
  final latStr = latlng.latitude.toStringAsFixed(6);
  final lngStr = latlng.longitude.toStringAsFixed(7);

  String msg = template;

  if (waypoints != null) {
    final nearestWaypoint = waypoints
        .where((e) => e.isPath == false && latlngCalc.distance(e.latlng.first, latlng) < 500)
        .toList()
        .sorted((a, b) =>
            (latlngCalc.distance(a.latlng.first, latlng) - latlngCalc.distance(b.latlng.first, latlng)).round())
        .firstOrNull;
    if (nearestWaypoint != null) {
      msg = msg.replaceAll("{near}", "near ${nearestWaypoint.name}:$latStr,$lngStr");
    }
  }
  msg = msg.replaceAll("{near}", "");

  // Macro substitutions
  msg = msg.replaceAll("{name}", pilotName ?? "");
  msg = msg.replaceAll("{google_maps}", "http://maps.google.com/maps?z=12&t=e&q=loc:$latlng+$lngStr");
  msg = msg.replaceAll("{location}", "$latStr,$lngStr");
  msg = msg.replaceAll("{time}", clock.now().toString());

  // Clean up double spaces left by empty substitutions
  msg = msg.replaceAll("  ", "");
  debugPrint("Sending SMS ${addresses.toString()}: $msg");
  _sendSMS(addresses, msg);
}
