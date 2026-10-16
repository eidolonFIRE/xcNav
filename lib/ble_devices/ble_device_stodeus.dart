import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/models/nmea.dart';

enum VarioStatus {
  /// Out of range, trying to reconnect
  disconnected,

  /// Connected, but no data lately
  connected,

  /// Data flowing
  receiving,
}

/// Stodeus varios (UltraBip, BlueBip).
/// Streams NMEA text over a BLE serial link: `$LK8EX1` baro at 10hz, and GGA/RMC at 1hz (UltraBip only, with a fix).
class BleDeviceStodeus extends BleDeviceHandler {
  /// Serial (service, notify characteristic) pairs, in order of preference.
  /// The UltraBip uses the HM-10 style `ffe0`/`ffe1`. Nordic UART is kept in case other models use it.
  static const serialUuids = [
    ("ffe0", "ffe1"),
    ("6e400001-b5a3-f393-e0a9-e50e24dcca9e", "6e400003-b5a3-f393-e0a9-e50e24dcca9e"),
  ];

  /// Data older than this counts as stale
  static const dataTimeout = Duration(seconds: 5);

  final ValueNotifier<VarioStatus> status = ValueNotifier(VarioStatus.disconnected);

  /// User has a vario selected (connected, or reconnecting after dropping out of BLE range).
  final ValueNotifier<bool> attached = ValueNotifier(false);

  BluetoothDevice? _device;

  @override
  BluetoothDevice? get device => _device;

  @override
  set device(BluetoothDevice? value) {
    _device = value;
    attached.value = value != null;
    if (value == null) _setStatus(VarioStatus.disconnected);
  }

  StreamSubscription<List<int>>? _listener;
  Timer? _dataWatchdog;
  final NmeaLineSplitter _splitter = NmeaLineSplitter();
  final NmeaFixAssembler _fixAssembler = NmeaFixAssembler();

  /// Pressure (hPa) and the device's own vario (m/s)
  void Function(double pressure, double? vario)? onBaro;
  void Function(Position position)? onPosition;

  final ValueNotifier<double?> batteryPercent = ValueNotifier(null);

  /// Celsius
  final ValueNotifier<double?> temperature = ValueNotifier(null);

  @override
  Map<String, dynamic>? toJson() => null;

  @override
  Future onConnected(BluetoothDevice instance) async {
    await super.onConnected(instance);

    BluetoothCharacteristic? tx;
    for (final (serviceUuid, txUuid) in serialUuids) {
      tx = characteristics[serviceUuid]?[txUuid];
      if (tx != null) break;
    }
    if (tx == null) {
      debugPrint("Stodeus - no serial characteristic found. Services: "
          "${characteristics.map((service, chars) => MapEntry(service, chars.keys.toList()))}");
      return;
    }
    debugPrint("Stodeus - subscribing to ${tx.uuid}");
    _listener?.cancel();
    _splitter.clear();
    _fixAssembler.clear();
    _resetStats();
    _listener = tx.onValueReceived.listen(handleBytes);
    _setStatus(VarioStatus.connected);
    try {
      await tx.setNotifyValue(true);
      debugPrint("Stodeus - notifications enabled, waiting for data");
    } catch (error) {
      debugPrint("Stodeus - failed to enable notifications: $error");
    }
  }

  @override
  void onDisconnected() {
    super.onDisconnected();
    _listener?.cancel();
    _listener = null;
    _setStatus(VarioStatus.disconnected);
  }

  void _setStatus(VarioStatus value) {
    _dataWatchdog?.cancel();
    _dataWatchdog = null;
    if (status.value != value) debugPrint("Stodeus - status ${status.value.name} -> ${value.name}");
    status.value = value;
  }

  // --- Debug stats, printed every [_statsInterval]
  static const _statsInterval = Duration(seconds: 5);
  DateTime _statsStart = DateTime(0);
  int _statBytes = 0;
  int _statBadLines = 0;
  final Map<String, int> _statSentences = {};
  int _statFixes = 0;
  Lk8ex1? _statLastLk8;
  String? _statLastLine;

  void _resetStats() {
    _statsStart = DateTime.now();
    _statBytes = 0;
    _statBadLines = 0;
    _statSentences.clear();
    _statFixes = 0;
  }

  void _printStats() {
    final lk8 = _statLastLk8;
    debugPrint("Stodeus - ${_statsInterval.inSeconds}s: $_statBytes bytes, sentences $_statSentences, "
        "$_statBadLines bad, $_statFixes fixes"
        "${lk8 == null ? "" : ", ${lk8.pressure} hPa, ${lk8.vario} m/s, ${lk8.temperature} C, ${lk8.batteryPercent}%"}"
        ", last: $_statLastLine");
    _resetStats();
  }

  void handleBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    if (status.value != VarioStatus.receiving) debugPrint("Stodeus - receiving data");
    _setStatus(VarioStatus.receiving);
    _dataWatchdog = Timer(dataTimeout, () => _setStatus(VarioStatus.connected));
    _statBytes += bytes.length;
    for (final line in _splitter.add(bytes)) {
      handleSentence(line);
    }
    if (DateTime.now().difference(_statsStart) > _statsInterval) _printStats();
  }

  void handleSentence(String line) {
    _statLastLine = line;
    final body = nmeaBody(line);
    if (body == null) {
      _statBadLines++;
      return;
    }
    final type = body.split(",").first;
    _statSentences[type] = (_statSentences[type] ?? 0) + 1;

    final lk8 = Lk8ex1.parse(body);
    if (lk8 != null) {
      _statLastLk8 = lk8;
      if (lk8.pressure != null) onBaro?.call(lk8.pressure!, lk8.vario);
      if (lk8.batteryPercent != null) batteryPercent.value = lk8.batteryPercent;
      if (lk8.temperature != null) temperature.value = lk8.temperature;
      return;
    }

    final gga = NmeaGga.parse(body);
    final rmc = gga == null ? NmeaRmc.parse(body) : null;
    final position = gga != null
        ? _fixAssembler.addGga(gga)
        : rmc != null
            ? _fixAssembler.addRmc(rmc)
            : null;
    if (position != null) {
      _statFixes++;
      onPosition?.call(position);
    }
  }
}
