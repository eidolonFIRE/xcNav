import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:xcnav/models/ga.dart';
import 'package:xcnav/models/geo.dart';

import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/units.dart';

enum TtsState { playing, stopped }

class ProximityConfig {
  final double vertical;
  final double horizontalDist;
  final double horizontalTime;

  /// Units in meters and seconds
  ProximityConfig(
      {required this.vertical,
      required this.horizontalDist,
      required this.horizontalTime});

  String toMultilineString(Settings settings) {
    return "Vertical: ${(convertDistValueFine(settings.displayUnitsDist, vertical) / 50).ceil() * 50}${unitStrDistFine[settings.displayUnitsDist]}\n"
        "Horiz Dist: ${(convertDistValueFine(settings.displayUnitsDist, horizontalDist) / 100).ceil() * 100}${unitStrDistFine[settings.displayUnitsDist]}\n"
        "Horiz Time: ${horizontalTime.toStringAsFixed(0)} sec";
  }
}

class ADSB with ChangeNotifier {
  RawDatagramSocket? sock;
  Map<int, GA> planes = {};

  late FlutterTts flutterTts;
  TtsState ttsState = TtsState.stopped;
  late final BuildContext context;

  int lastHeartbeat = 0;

  bool portListening = false;

  ADSB(BuildContext ctx) {
    context = ctx;

    flutterTts = FlutterTts();
    flutterTts.awaitSpeakCompletion(true);
    flutterTts.setStartHandler(() {
      ttsState = TtsState.playing;
    });

    flutterTts.setCompletionHandler(() {
      ttsState = TtsState.stopped;
    });

    flutterTts.setCancelHandler(() {
      ttsState = TtsState.stopped;
    });

    flutterTts.setErrorHandler((msg) {
      ttsState = TtsState.stopped;
    });

    Provider.of<Settings>(context, listen: false).addListener(() {
      var settings = Provider.of<Settings>(context, listen: false);
      debugPrint("-----");
      if (!portListening && settings.adsbEnabled) {
        // --- Start Listening
        debugPrint("Opening ADSB listen port 4000");
        RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 4000)
            .then((_sock) {
          sock = _sock;

          _sock.listen((event) {
            // debugPrint("ADSB event: ${event.toString()}");
            Datagram? dg = _sock.receive();
            if (dg != null) {
              // debugPrint("${dg.data.toString()}");
              decodeGDL90(dg.data);
            }
          }, onError: (error) {
            debugPrint("ADSB socket error: ${error.toString()}");
          }, onDone: () {
            debugPrint("ADSB socket done.");
          });
        });
        portListening = true;
      } else if (portListening && !settings.adsbEnabled) {
        // --- Stop Listening
        debugPrint("Closing ADSB listen port");
        sock?.close();
        portListening = false;
      }
    });
  }

  @override
  void dispose() {
    if (sock != null) sock!.close();
    super.dispose();
    flutterTts.stop();
  }

  int decode24bit(Uint8List data) {
    int value = ((data[0] & 0x7f) << 16) | (data[1] << 8) | data[2];
    if (data[0] & 0x80 > 0) {
      value -= 0x7fffff;
    }
    return value;
  }

  void decodeTraffic(Uint8List data) {
    final int id = (data[1] << 16) | (data[2] << 8) | data[3];

    final double lat = decode24bit(data.sublist(4, 7)) * 180.0 / 0x7fffff;
    final double lng = decode24bit(data.sublist(7, 10)) * 180.0 / 0x7fffff;

    final Uint8List _altRaw = data.sublist(10, 12);
    final double alt =
        ((((_altRaw[0] << 4) + (_altRaw[1] >> 4)) * 25) - 1000) / meters2Feet;

    final double hdg = data[16] * 360 / 256.0;
    final double spd = ((data[13] << 4) + (data[14] >> 4)) * 0.51444;

    // TODO: why are we getting really high IDs? (reserved IDs)
    GAtype type = GAtype.unknown;
    final i = data[17];
    if (i == 1 || i == 9 || i == 10) {
      type = GAtype.small;
    } else if (i == 7) {
      type = GAtype.heli;
    } else {
      type = GAtype.large;
    }

    debugPrint(
        "GA $id (${type.toString()}): $lat, $lng, $spd m/s  $alt m, $hdg deg");

    if (type.index > 0 &&
        type.index < 22 &&
        (lat != 0 || lng != 0) &&
        (lat < 90 && lat > -90)) {
      planes[id] = GA(id, LatLng(lat, lng), alt, spd, hdg, type,
          DateTime.now().millisecondsSinceEpoch);
    }
  }

  void decodeGDL90(Uint8List data) {
    switch (data[1]) {
      case 0:
        // --- heartbeat
        // debugPrint("ADSB heartbeat ${data[2].toRadixString(2)}");
        if (data[2] & 0x50 == 0) {
          lastHeartbeat = DateTime.now().millisecondsSinceEpoch;
        }

        break;
      case 20:
        // --- traffic
        decodeTraffic(data.sublist(2));
        break;
      default:
        break;
    }
  }

  void cleanupOldEntries() {
    final thresh = DateTime.now().millisecondsSinceEpoch - 1000 * 12;
    for (GA each in planes.values.toList()) {
      if (each.timestamp < thresh) planes.remove(each.id);
    }
  }

  /// Wrap delta heading to +/- 180deg
  double deltaHdg(double a, double b) {
    return (a - b + 180) % 360 - 180;
  }

  void checkProximity(Geo observer) {
    ProximityConfig config =
        Provider.of<Settings>(context, listen: false).proximityProfile;

    for (GA each in planes.values) {
      final double dist = latlngCalc.distance(each.latlng, observer.latLng);
      final double bearing = latlngCalc.bearing(each.latlng, observer.latLng);

      final double delta = deltaHdg(bearing, each.hdg).abs();

      final double tangentOffset = sin(delta * pi / 180) * dist;
      final double altOffset = each.alt - observer.alt;

      // TODO: deduce speed if not provided?
      final double? eta =
          (each.spd > 0 && delta < 30 && tangentOffset < config.horizontalDist)
              ? dist / each.spd
              : null;

      final bool warning =
          (((eta ?? double.infinity) < config.horizontalTime) ||
                  dist < config.horizontalDist) &&
              altOffset.abs() < config.vertical;

      planes[each.id]!.warning = warning;

      if (warning && ttsState == TtsState.stopped) {
        speakWarning(each, observer, eta);
      }
    }
  }

  void testWarning() {
    ProximityConfig config =
        Provider.of<Settings>(context, listen: false).proximityProfile;
    var rand = Random(DateTime.now().millisecondsSinceEpoch);
    var observer = LatLng(0, 0);

    var ga = GA(
        0,
        latlngCalc.offset(LatLng(0, 0), 10 + rand.nextDouble() * 3000,
            rand.nextDouble() * 360),
        rand.nextDouble() * 200 - 100,
        35 + rand.nextDouble() * 50,
        rand.nextDouble() * 360,
        GAtype.values[rand.nextInt(GAtype.values.length)],
        DateTime.now().millisecondsSinceEpoch);

    final double dist = latlngCalc.distance(ga.latlng, observer);
    final double bearing = latlngCalc.bearing(ga.latlng, observer);

    final double delta = deltaHdg(bearing, ga.hdg).abs();

    final double tangentOffset = sin(delta * pi / 180) * dist;
    final double? eta =
        (ga.spd > 0 && delta < 30 && tangentOffset < config.horizontalDist)
            ? dist / ga.spd
            : null;
    speakWarning(
        ga,
        Geo.fromValues(0, 0, 0, DateTime.now().millisecondsSinceEpoch,
            rand.nextDouble() * 2 * pi, 11.15 + 4.5 * rand.nextDouble(), 0),
        eta);
  }

  void speakWarning(GA ga, Geo observer, double? eta) {
    final settings = Provider.of<Settings>(context, listen: false);

    // direction
    final int oclock = (((deltaHdg(
                            latlngCalc.bearing(observer.latLng, ga.latlng),
                            observer.hdg * 180 / pi) /
                        360.0 *
                        12.0)
                    .round() +
                11) %
            12) +
        1;

    // distance, eta
    final int dist = convertDistValueCoarse(settings.displayUnitsDist,
            latlngCalc.distance(ga.latlng, observer.latLng))
        .toInt();
    final String distMsg =
        ((dist > 0) ? dist.toStringAsFixed(0) : "less than one") +
            unitStrDistCoarseVerbal[settings.displayUnitsDist]!;
    final String? etaStr =
        eta != null ? eta.toStringAsFixed(0) + " seconds out" : null;

    // vertical separation
    String vertSep = ".";
    final double altOffset = ga.alt - observer.alt;
    if (altOffset > 100) vertSep = " high.";
    if (altOffset < -100) vertSep = " low.";

    // Type
    final String typeStr = gaTypeStr[ga.type] ?? "";

    String msg =
        "Warning! $typeStr $oclock o'clock$vertSep ${etaStr ?? distMsg}... ";
    debugPrint(msg);
    flutterTts.setVolume(1);
    flutterTts.speak(msg);
  }

  /// Trigger update refresh
  /// Provide observer geo to calculate warnings
  void refresh(Geo observer) {
    if (planes.isNotEmpty) {
      cleanupOldEntries();
      checkProximity(observer);
      notifyListeners();
    }
  }
}
