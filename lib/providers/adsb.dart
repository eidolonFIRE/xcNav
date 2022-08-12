import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:xcnav/main.dart';

import 'package:xcnav/models/ga.dart';
import 'package:xcnav/models/geo.dart';

import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/tts_service.dart';
import 'package:xcnav/units.dart';

import 'package:xcnav/models/gdl90.dart' as gdl90;
import 'package:xcnav/models/mavlink.dart' as mavlink;

enum TtsState { playing, stopped }

class ProximityConfig {
  final double vertical;
  final double horizontalDist;
  final double horizontalTime;

  /// Units in meters and seconds
  ProximityConfig({required this.vertical, required this.horizontalDist, required this.horizontalTime});

  String toMultilineString(Settings settings) {
    return "Vertical: ${(convertDistValueFine(settings.displayUnitsDist, vertical) / 50).ceil() * 50}${unitStrDistFine[settings.displayUnitsDist]}\n"
        "Horiz Dist: ${(convertDistValueFine(settings.displayUnitsDist, horizontalDist) / 100).ceil() * 100}${unitStrDistFine[settings.displayUnitsDist]}\n"
        "Horiz Time: ${horizontalTime.toStringAsFixed(0)} sec";
  }
}

class ADSB with ChangeNotifier {
  RawDatagramSocket? sock;
  Map<String, GA> planes = {};

  TtsState ttsState = TtsState.stopped;
  late final BuildContext context;

  int lastHeartbeat = 0;

  bool portListening = false;
  bool _enabled = false;

  UsbPort? _usbPort;

  StreamSubscription<Uint8List>? _subscription;
  Transaction<Uint8List>? _transaction;
  UsbDevice? _device;

  Future<bool> _connectTo(UsbDevice? device) async {
    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }

    if (_transaction != null) {
      _transaction!.dispose();
      _transaction = null;
    }

    if (_usbPort != null) {
      _usbPort!.close();
      _usbPort = null;
    }

    if (device == null) {
      _device = null;
      return true;
    }

    try {
      _usbPort = await device.create();
      if (await (_usbPort!.open()) != true) {
        debugPrint("USB PORT FAILED TO OPEN");
        return false;
      }
      _device = device;

      await _usbPort!.setDTR(true);
      await _usbPort!.setRTS(true);
      await _usbPort!.setPortParameters(57600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      _transaction = Transaction.magicHeader(_usbPort!.inputStream as Stream<Uint8List>, [0xFE, 38]);
      _subscription = _transaction!.stream.listen((data) {
        final ga = mavlink.decodeMavlink(data);
        if (ga != null) {
          planes[ga.id] = ga;
          heartbeat();
        }
      }, onError: (e) {
        debugPrint("USB SERIAL ERROR: ${e.toString()}");
      }, onDone: () {
        debugPrint("USB SERIAL DONE");
      }, cancelOnError: false);
      debugPrint("USB PORT CONNECTED");
      return true;
    } catch (e) {
      debugPrint("USB SERIAL GENERAL ERROR: ${e.toString()}");
      return false;
    }
  }

  void _getPorts() async {
    List<UsbDevice> devices = await UsbSerial.listDevices();
    if (!devices.contains(_device)) {
      _connectTo(null);
    }

    for (final device in devices) {
      debugPrint("${device.productName}, ${device.serial}, ${device.pid}, ${device.vid}");
      if ((device.productName ?? "").contains("UART")) {
        _connectTo(device);
      }
    }
  }

  ADSB(BuildContext ctx) {
    context = ctx;

    if (Platform.isAndroid) {
      UsbSerial.usbEventStream!.listen((UsbEvent event) {
        _getPorts();
      });

      _getPorts();
    }
  }

  bool get enabled => _enabled;
  set enabled(bool value) {
    _enabled = value;
    refreshSocket();
    notifyListeners();
  }

  @override
  void dispose() {
    if (sock != null) sock!.close();
    super.dispose();
    if (Platform.isAndroid) {
      _connectTo(null);
    }
  }

  void refreshSocket() async {
    if (!portListening && _enabled) {
      // --- Start Listening
      final info = NetworkInfo();
      var wifiName = await info.getWifiName();
      var wifiGateway = await info.getWifiGatewayIP();

      debugPrint("WifiName: $wifiName, WifiGateway: $wifiGateway");

      dynamic address = InternetAddress.loopbackIPv4;
      if (wifiName != null && (wifiName.startsWith("Ping-") || wifiName.startsWith("Sentry_"))) {
        // Temporary hard coded for Ping...
        address = wifiGateway ?? "0.0.0.0";
      }

      debugPrint("Opening ADSB listen on ${address.toString()}:4000");
      RawDatagramSocket.bind(address, 4000).then((sock) {
        sock = sock;

        sock.listen((event) {
          // debugPrint("ADSB event: ${event.toString()}");
          Datagram? dg = sock.receive();
          if (dg != null) {
            // debugPrint("${dg.data.toString()}");
            heartbeat();
            final ga = gdl90.decodeGDL90(dg.data);
            if (ga != null) {
              planes[ga.id] = ga;
            }
          }
        }, onError: (error) {
          debugPrint("ADSB socket error: ${error.toString()}");
        }, onDone: () {
          debugPrint("ADSB socket done.");
        });
      });
      portListening = true;
    } else if (portListening && !_enabled) {
      // --- Stop Listening
      debugPrint("Closing ADSB listen port");
      lastHeartbeat = 0;
      sock?.close();
      portListening = false;
    }
  }

  void heartbeat() {
    lastHeartbeat = DateTime.now().millisecondsSinceEpoch;
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
    ProximityConfig config = Provider.of<Settings>(context, listen: false).proximityProfile;

    for (GA each in planes.values) {
      final double dist = latlngCalc.distance(each.latlng, observer.latLng);
      final double bearing = latlngCalc.bearing(each.latlng, observer.latLng);

      final double delta = deltaHdg(bearing, each.hdg).abs();

      final double tangentOffset = sin(delta * pi / 180) * dist;
      final double altOffset = each.alt - observer.alt;

      // TODO: deduce speed if not provided?
      final double? eta =
          (each.spd > 0 && delta < 30 && tangentOffset < config.horizontalDist) ? dist / each.spd : null;

      final bool warning = (((eta ?? double.infinity) < config.horizontalTime) || dist < config.horizontalDist) &&
          altOffset.abs() < config.vertical;

      planes[each.id]!.warning = warning;

      if (warning && ttsState == TtsState.stopped) {
        speakWarning(each, observer, eta);
      }
    }
  }

  void testWarning() {
    ProximityConfig config = Provider.of<Settings>(context, listen: false).proximityProfile;
    var rand = Random(DateTime.now().millisecondsSinceEpoch);
    var observer = LatLng(0, 0);

    var ga = GA(
        "",
        latlngCalc.offset(LatLng(0, 0), 10 + rand.nextDouble() * 3000, rand.nextDouble() * 360),
        rand.nextDouble() * 200 - 100,
        35 + rand.nextDouble() * 50,
        rand.nextDouble() * 360,
        GAtype.values[rand.nextInt(GAtype.values.length)],
        DateTime.now().millisecondsSinceEpoch);

    final double dist = latlngCalc.distance(ga.latlng, observer);
    final double bearing = latlngCalc.bearing(ga.latlng, observer);

    final double delta = deltaHdg(bearing, ga.hdg).abs();

    final double tangentOffset = sin(delta * pi / 180) * dist;
    final double? eta = (ga.spd > 0 && delta < 30 && tangentOffset < config.horizontalDist) ? dist / ga.spd : null;
    speakWarning(
        ga,
        Geo.fromValues(0, 0, 0, DateTime.now().millisecondsSinceEpoch, rand.nextDouble() * 2 * pi,
            11.15 + 4.5 * rand.nextDouble(), 0),
        eta);
  }

  void speakWarning(GA ga, Geo observer, double? eta) {
    final settings = Provider.of<Settings>(context, listen: false);

    // direction
    final int oclock =
        (((deltaHdg(latlngCalc.bearing(observer.latLng, ga.latlng), observer.hdg * 180 / pi) / 360.0 * 12.0).round() +
                    11) %
                12) +
            1;

    // distance, eta
    final dist = convertDistValueCoarse(settings.displayUnitsDist, latlngCalc.distance(ga.latlng, observer.latLng));
    final String distMsg = printValueLexical(value: dist) + unitStrDistCoarseLexical[settings.displayUnitsDist]!;
    final String? etaStr = eta != null ? "${eta.toStringAsFixed(0)} seconds out" : null;

    // vertical separation
    String vertSep = ".";
    final double altOffset = ga.alt - observer.alt;
    if (altOffset > 100) vertSep = " high.";
    if (altOffset < -100) vertSep = " low.";

    // Type
    final String typeStr = gaTypeStr[ga.type] ?? "";

    String msg = "Warning! $typeStr $oclock o'clock$vertSep ${etaStr ?? distMsg}... ";
    debugPrint(msg);
    ttsService
        .speak(AudioMessage(msg, priority: 0, expires: DateTime.now().add(const Duration(seconds: 20)), volume: 1));
  }

  /// Trigger update refresh
  /// Provide observer geo to calculate warnings
  void refresh(Geo observer) {
    if (planes.isNotEmpty) {
      cleanupOldEntries();
      if (_enabled) checkProximity(observer);
      notifyListeners();
    }
  }
}
