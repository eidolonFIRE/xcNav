import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';
import 'package:flutter_serial_communication/models/device_info.dart';
import 'package:latlong2/latlong.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:xcnav/datadog.dart';

import 'package:xcnav/models/ga.dart';
import 'package:xcnav/models/geo.dart';

import 'package:xcnav/settings_service.dart';
import 'package:xcnav/tts_service.dart';
import 'package:xcnav/units.dart';

import 'package:xcnav/models/gdl90.dart' as gdl90;
import 'package:xcnav/models/mavlink.dart' as mavlink;
import 'package:xcnav/util.dart';

enum ProximitySize {
  off,
  small,
  medium,
  large,
  xlarge,
}

final Map<ProximitySize, ProximityConfig> proximityProfileOptions = {
  ProximitySize.off: ProximityConfig(vertical: 0, horizontalDist: 0, horizontalTime: 0),
  ProximitySize.small: ProximityConfig(vertical: 200, horizontalDist: 600, horizontalTime: 30),
  ProximitySize.medium: ProximityConfig(vertical: 400, horizontalDist: 1200, horizontalTime: 45),
  ProximitySize.large: ProximityConfig(vertical: 800, horizontalDist: 2000, horizontalTime: 60),
  ProximitySize.xlarge: ProximityConfig(vertical: 1200, horizontalDist: 3000, horizontalTime: 90),
};

class ProximityConfig {
  final double vertical;
  final double horizontalDist;
  final double horizontalTime;

  /// Units in meters and seconds
  ProximityConfig({required this.vertical, required this.horizontalDist, required this.horizontalTime});

  String toMultilineString() {
    return "Vertical: ${(unitConverters[UnitType.distFine]!(vertical) / 50).ceil() * 50}${getUnitStr(UnitType.distFine)}\n"
        "Horiz Dist: ${(unitConverters[UnitType.distFine]!(horizontalDist) / 100).ceil() * 100}${getUnitStr(UnitType.distFine)}\n"
        "Horiz Time: ${horizontalTime.toStringAsFixed(0)} sec";
  }
}

class ADSB with ChangeNotifier {
  RawDatagramSocket? sock;
  Map<String, GA> planes = {};

  late final BuildContext context;

  int lastHeartbeat = 0;

  bool portListening = false;
  bool _enabled = false;

  final FlutterSerialCommunication _serial = FlutterSerialCommunication();
  final mavlink.MavlinkFramer _framer = mavlink.MavlinkFramer();

  StreamSubscription? _serialSubscription;
  StreamSubscription? _connectionSubscription;
  Timer? _usbPollTimer;
  DeviceInfo? _device;
  bool _connecting = false;

  /// Devices that failed to connect (or were denied permission). Not retried until unplugged.
  final Set<String> _failedDevices = {};

  /// Planes in [planes] that came from the server rather than our own receiver.
  final Set<String> _serverPlaneIds = {};

  /// Our own receiver's reports not yet echoed to the server. (Latest per plane)
  final Map<String, GA> _pendingObserved = {};

  /// Our own receiver has been heard from recently. When true, server reports are ignored.
  bool get hasLocalSource =>
      _device != null || lastHeartbeat > DateTime.now().millisecondsSinceEpoch - localSourceTimeout.inMilliseconds;

  static const Duration localSourceTimeout = Duration(seconds: 15);

  /// Report from our own receiver (USB or wifi).
  @visibleForTesting
  void addLocalPlane(GA ga) {
    if (settingsMgr.adsbFilters.value.contains(ga.id)) return;
    // Our receiver takes over from the server.
    if (_serverPlaneIds.isNotEmpty) {
      planes.removeWhere((id, _) => _serverPlaneIds.contains(id));
      _serverPlaneIds.clear();
    }
    planes[ga.id] = ga;
    _pendingObserved[ga.id] = ga;
  }

  /// Reports relayed by the server from other pilots' receivers.
  void addServerPlanes(Iterable<GA> reports) {
    if (hasLocalSource) return;
    for (final ga in reports) {
      if (settingsMgr.adsbFilters.value.contains(ga.id)) continue;
      final existing = planes[ga.id];
      if (existing != null && existing.timestamp > ga.timestamp) continue;
      planes[ga.id] = ga;
      _serverPlaneIds.add(ga.id);
    }
  }

  /// Take our receiver's reports that still need to be sent to the server.
  /// With [near], only reports within [range] meters of it are returned. (Others are still cleared.)
  List<GA> takeObserved({LatLng? near, double range = double.infinity}) {
    final list = _pendingObserved.values
        .where((e) => near == null || latlngCalc.distance(e.latlng, near) <= range)
        .toList();
    _pendingObserved.clear();
    return list;
  }

  void _onSerialData(dynamic data) {
    if (data is! Uint8List) return;
    for (final frame in _framer.add(data)) {
      final ga = mavlink.decodeMavlink(frame);
      if (ga != null) {
        heartbeat();
        addLocalPlane(ga);
      }
    }
  }

  Future<bool> _connectTo(DeviceInfo device) async {
    _connecting = true;
    try {
      _framer.clear();
      if (!await _serial.connect(device, 57600)) {
        debugPrint("USB PORT FAILED TO OPEN");
        return false;
      }
      _device = device;

      await _serial.setDTR(true);
      await _serial.setRTS(true);

      debugPrint("USB PORT CONNECTED");
      return true;
    } catch (err, trace) {
      error("USB error (adsb)", errorMessage: err.toString(), errorStackTrace: trace);
      return false;
    } finally {
      _connecting = false;
    }
  }

  Future<void> _disconnect() async {
    if (_device == null) return;
    _device = null;
    _framer.clear();
    try {
      await _serial.disconnect();
    } catch (err, trace) {
      error("USB error (adsb)", errorMessage: err.toString(), errorStackTrace: trace);
    }
  }

  void _getPorts() async {
    if (_connecting) return;
    final List<DeviceInfo> devices;
    try {
      devices = await _serial.getAvailableDevices();
    } catch (err) {
      debugPrint("USB list devices failed: $err");
      return;
    }
    final names = devices.map((e) => e.deviceName).toSet();

    // Allow retry once a failed device is unplugged.
    _failedDevices.retainWhere(names.contains);

    if (_device != null && !names.contains(_device!.deviceName)) {
      await _disconnect();
    }
    if (_device != null) return;

    for (final device in devices) {
      if (_failedDevices.contains(device.deviceName)) continue;
      debugPrint("${device.productName}, ${device.serialNumber}, ${device.productId}, ${device.vendorId}");
      if (device.productName.contains("UART")) {
        if (await _connectTo(device)) {
          // Go ahead and turn ADSB on.
          enabled = true;
        } else {
          _failedDevices.add(device.deviceName);
        }
        break;
      }
    }
  }

  ADSB(BuildContext ctx) {
    context = ctx;

    if (Platform.isAndroid) {
      _serialSubscription = _serial.getSerialMessageListener().receiveBroadcastStream().listen(_onSerialData,
          onError: (e) {
        debugPrint("USB SERIAL ERROR: ${e.toString()}");
      }, cancelOnError: false);

      _connectionSubscription = _serial.getDeviceConnectionListener().receiveBroadcastStream().listen((connected) {
        if (connected == false && _device != null) {
          debugPrint("USB SERIAL DISCONNECTED");
          _device = null;
          _framer.clear();
        }
      });

      // No USB attach/detach events in flutter_serial_communication, so poll.
      _usbPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _getPorts());
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
      _usbPollTimer?.cancel();
      _serialSubscription?.cancel();
      _connectionSubscription?.cancel();
      _disconnect();
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
      if (wifiName != null && wifiName.contains("Ping-")) {
        // Temporary hard coded for Ping...
        debugPrint("Ping / Sentry wifi detected.");
        address = "0.0.0.0";
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
            if (ga != null) addLocalPlane(ga);
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
      if (each.timestamp < thresh) {
        planes.remove(each.id);
        _serverPlaneIds.remove(each.id);
      }
    }
  }

  /// Wrap delta heading to +/- 180deg
  double deltaHdg(double a, double b) {
    return (a - b + 180) % 360 - 180;
  }

  void checkProximity(Geo observer) {
    ProximityConfig config = proximityProfileOptions[settingsMgr.adsbProximitySize.value]!;

    for (GA each in planes.values) {
      final double dist = latlngCalc.distance(each.latlng, observer.latlng);
      final double bearing = latlngCalc.bearing(each.latlng, observer.latlng);

      final double delta = deltaHdg(bearing, each.hdg).abs();

      final double tangentOffset = sin(delta * pi / 180) * dist;
      final double altOffset = each.alt - observer.alt;

      final double? eta =
          (each.spd > 0 && delta < 30 && tangentOffset < config.horizontalDist) ? dist / each.spd : null;

      final bool warning = (((eta ?? double.infinity) < config.horizontalTime) || dist < config.horizontalDist) &&
          altOffset.abs() < config.vertical;

      planes[each.id]!.warning = warning;

      if (warning) {
        speakWarning(each, observer, eta);
      }
    }
  }

  void testWarning() {
    ProximityConfig config = proximityProfileOptions[settingsMgr.adsbProximitySize.value]!;
    var rand = Random(DateTime.now().millisecondsSinceEpoch);
    var observer = const LatLng(0, 0);

    var ga = GA(
        "",
        latlngCalc.offset(const LatLng(0, 0), 10 + rand.nextDouble() * 3000, rand.nextDouble() * 360),
        rand.nextDouble() * 200 - 100,
        35 + rand.nextDouble() * 50,
        rand.nextDouble() * 360,
        GAtype.values[rand.nextInt(GAtype.values.length - 1) + 1],
        DateTime.now().millisecondsSinceEpoch);

    final double dist = latlngCalc.distance(ga.latlng, observer);
    final double bearing = latlngCalc.bearing(ga.latlng, observer);

    final double delta = deltaHdg(bearing, ga.hdg).abs();

    final double tangentOffset = sin(delta * pi / 180) * dist;
    final double? eta = (ga.spd > 0 && delta < 30 && tangentOffset < config.horizontalDist) ? dist / ga.spd : null;
    speakWarning(
        ga,
        Geo(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            hdg: rand.nextDouble() * 2 * pi,
            spd: 11.15 + 4.5 * rand.nextDouble()),
        eta);
  }

  void speakWarning(GA ga, Geo observer, double? eta) {
    // direction
    final int oclock =
        (((deltaHdg(latlngCalc.bearing(observer.latlng, ga.latlng), observer.hdg * 180 / pi) / 360.0 * 12.0).round() +
                    11) %
                12) +
            1;

    // distance, eta
    final dist = unitConverters[UnitType.distCoarse]!(latlngCalc.distance(ga.latlng, observer.latlng));
    final String distMsg = "${printDoubleLexical(value: dist)} ${getUnitStr(UnitType.distCoarse, lexical: true)}";
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
  void refresh(Geo observer, bool inFlight) {
    if (planes.isNotEmpty) {
      cleanupOldEntries();
      if (_enabled && inFlight) checkProximity(observer);
      notifyListeners();
    }
  }
}
