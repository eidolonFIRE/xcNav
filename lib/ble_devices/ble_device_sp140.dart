import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/ble_devices/ble_device_value.dart';
import 'package:xcnav/datadog.dart' as dd;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:convert/convert.dart';
import 'package:xcnav/units.dart';

class BleFastLinkTelemetry {
  static const int bmsCellsNum = 24;
  static const int tempSensorCount = 8;

  int version = 0;
  int packetId = 0;
  int uptimeMs = 0;

  int altitudeCm = 0;
  int baroTempDC = 0;
  int baroPressureDHPa = 0;
  int varioCmps = 0;
  int mcuTempDC = 0;
  int potRaw = 0;
  int deviceState = 0;

  int escStatus = 0;
  int escVoltsDV = 0;
  int escAmpsDA = 0;
  int escPhaseCurrentDA = 0;
  int escRpm = 0;
  int escTempMosDC = 0;
  int escTempCapDC = 0;
  int escTempMcuDC = 0;
  int escTempMotorDC = 0;
  int escInPWM = 0;
  int escOutPWM = 0;
  int escVModulation = 0;
  int escError = 0;
  int escSelfcheck = 0;
  int escHardwareId = 0;
  int escFwVersion = 0;
  int escBootloaderVersion = 0;
  int escRuntimeMs = 0;
  List<int> escSnCode = List<int>.filled(16, 0);

  int bmsStatus = 0;
  int bmsSoc = 0;
  int bmsVoltsDV = 0;
  int bmsAmpsDA = 0;
  int bmsEnergyCycleMAh = 0;
  int bmsBatteryCycle = 0;
  int bmsFailLevel = 0;
  int bmsIsCharging = 0;
  int bmsIsChargeMos = 0;
  int bmsIsDischargeMos = 0;
  int bmsChargeWire = 0;
  int bmsLowSocWarning = 0;
  int bmsBatteryReady = 0;
  int bmsHighestTempC = 0;
  int bmsLowestTempC = 0;
  int bmsCellMaxMV = 0;
  int bmsCellMinMV = 0;
  int bmsVoltageDiffMV = 0;
  String bmsBatteryId = '';
  int bmsType = 0;

  List<int> bmsCellVoltagesMV = List<int>.filled(bmsCellsNum, 0);
  List<int> bmsTempSensorsC = List<int>.filled(tempSensorCount, 0);

  BleFastLinkTelemetry();

  BleFastLinkTelemetry.fromListInt(List<int> data) {
    final bytes = Uint8List.fromList(data);
    final byteData = ByteData.sublistView(bytes);
    var offset = 0;

    version = byteData.getUint8(offset++);
    packetId = byteData.getUint32(offset, Endian.little);
    offset += 4;
    uptimeMs = byteData.getUint32(offset, Endian.little);
    offset += 4;

    altitudeCm = byteData.getInt32(offset, Endian.little);
    offset += 4;
    baroTempDC = byteData.getInt16(offset, Endian.little);
    offset += 2;
    baroPressureDHPa = byteData.getUint16(offset, Endian.little);
    offset += 2;
    varioCmps = byteData.getInt16(offset, Endian.little);
    offset += 2;
    mcuTempDC = byteData.getInt16(offset, Endian.little);
    offset += 2;
    potRaw = byteData.getUint16(offset, Endian.little);
    offset += 2;
    deviceState = byteData.getUint8(offset++);

    escStatus = byteData.getUint8(offset++);
    escVoltsDV = byteData.getUint16(offset, Endian.little);
    offset += 2;
    escAmpsDA = byteData.getInt16(offset, Endian.little);
    offset += 2;
    escPhaseCurrentDA = byteData.getInt16(offset, Endian.little);
    offset += 2;
    escRpm = byteData.getInt32(offset, Endian.little);
    offset += 4;
    escTempMosDC = byteData.getInt16(offset, Endian.little);
    offset += 2;
    escTempCapDC = byteData.getInt16(offset, Endian.little);
    offset += 2;
    escTempMcuDC = byteData.getInt16(offset, Endian.little);
    offset += 2;
    escTempMotorDC = byteData.getInt16(offset, Endian.little);
    offset += 2;
    escInPWM = byteData.getUint16(offset, Endian.little);
    offset += 2;
    escOutPWM = byteData.getUint16(offset, Endian.little);
    offset += 2;
    escVModulation = byteData.getUint16(offset, Endian.little);
    offset += 2;
    escError = byteData.getUint16(offset, Endian.little);
    offset += 2;
    escSelfcheck = byteData.getUint16(offset, Endian.little);
    offset += 2;
    escHardwareId = byteData.getUint16(offset, Endian.little);
    offset += 2;
    escFwVersion = byteData.getUint16(offset, Endian.little);
    offset += 2;
    escBootloaderVersion = byteData.getUint16(offset, Endian.little);
    offset += 2;
    escRuntimeMs = byteData.getUint32(offset, Endian.little);
    offset += 4;
    for (var i = 0; i < escSnCode.length; i++) {
      escSnCode[i] = byteData.getUint8(offset++);
    }

    bmsStatus = byteData.getUint8(offset++);
    bmsSoc = byteData.getUint8(offset++);
    bmsVoltsDV = byteData.getUint16(offset, Endian.little);
    offset += 2;
    bmsAmpsDA = byteData.getInt16(offset, Endian.little);
    offset += 2;
    bmsEnergyCycleMAh = byteData.getUint32(offset, Endian.little);
    offset += 4;
    bmsBatteryCycle = byteData.getUint32(offset, Endian.little);
    offset += 4;
    bmsFailLevel = byteData.getUint8(offset++);
    bmsIsCharging = byteData.getUint8(offset++);
    bmsIsChargeMos = byteData.getUint8(offset++);
    bmsIsDischargeMos = byteData.getUint8(offset++);
    bmsChargeWire = byteData.getUint8(offset++);
    bmsLowSocWarning = byteData.getUint8(offset++);
    bmsBatteryReady = byteData.getUint8(offset++);
    bmsHighestTempC = byteData.getInt8(offset++);
    bmsLowestTempC = byteData.getInt8(offset++);
    bmsCellMaxMV = byteData.getUint16(offset, Endian.little);
    offset += 2;
    bmsCellMinMV = byteData.getUint16(offset, Endian.little);
    offset += 2;
    bmsVoltageDiffMV = byteData.getUint16(offset, Endian.little);
    offset += 2;

    final idBytes = <int>[];
    while (offset < byteData.lengthInBytes && byteData.getUint8(offset) != 0) {
      idBytes.add(byteData.getUint8(offset++));
    }
    offset++;
    bmsBatteryId = String.fromCharCodes(idBytes);
    bmsType = byteData.getUint8(offset++);

    for (var i = 0; i < bmsCellVoltagesMV.length; i++) {
      bmsCellVoltagesMV[i] = byteData.getUint16(offset, Endian.little);
      offset += 2;
    }

    for (var i = 0; i < bmsTempSensorsC.length; i++) {
      bmsTempSensorsC[i] = byteData.getInt8(offset++);
    }
  }
}

class Sp140TelemetryCharacteristic {
  final String uuid;
  BluetoothCharacteristic? characteristic;
  StreamSubscription<List<int>>? _listener;

  final rpm = BleLoggedValue<int>();
  final voltage = BleLoggedValue<double>();
  final amps = BleLoggedValue<double>();

  Sp140TelemetryCharacteristic({required this.uuid});

  void stopRefresh() {
    _listener?.cancel();
    _listener = null;
  }

  void setupRefreshTimer(BluetoothCharacteristic bleChar) {
    characteristic = bleChar;
    stopRefresh();

    characteristic?.setNotifyValue(true);
    _listener = characteristic?.onValueReceived.listen((data) {
      dd.info("Sp140 Telemetry Data Received: ${hex.encode(data)}", attributes: {"char_uuid": uuid});
      final telemetry = BleFastLinkTelemetry.fromListInt(data);
      rpm.addValue(telemetry.escRpm, clock.now());
      voltage.addValue(telemetry.escVoltsDV / 10.0, clock.now());
      amps.addValue(telemetry.escAmpsDA / 10.0, clock.now());
    });
  }

  Map<String, dynamic>? toJson() {
    return {
      "rpm": rpm,
      "voltage": voltage,
      "amps": amps,
    };
  }

  void trimToRange(DateTimeRange range) {
    rpm.trimToRange(range);
  }
}

class Sp140CommandCharacteristic {
  final String uuid;
  BluetoothCharacteristic? characteristic;
  StreamSubscription<List<int>>? _listener;

  Sp140CommandCharacteristic({required this.uuid});

  void stopRefresh() {
    _listener?.cancel();
    _listener = null;
  }

  void setupRefreshTimer(BluetoothCharacteristic bleChar) {
    characteristic = bleChar;
    stopRefresh();
  }

  Future<void> push(List<int> data) async {
    debugPrint("RunLeader: Pushing Config ${data.map((e) => e.toRadixString(16)).toList()}");
    await characteristic?.write(data).catchError((error) {
      dd.error("Writing config characteristic",
          errorMessage: error.toString(), errorKind: "BLE", attributes: {"char_uuid": uuid});
    });
  }

  Map<String, dynamic>? toJson() {
    // Config saves nothing
    return null;
  }
}

//---------------------------

class BleDeviceSp140 extends BleDeviceHandler {
  @override
  // ignore: overridden_fields, non_constant_identifier_names
  final SERVICE_UUID = "45A17001-B73B-49E1-8B39-5E9ED5E1B930";
  // ignore: non_constant_identifier_names
  final SERVICE_UUID_SHORT = "7001";

  BleDeviceSp140() : super();

  final Sp140TelemetryCharacteristic telemetry =
      Sp140TelemetryCharacteristic(uuid: "45A17002-B73B-49E1-8B39-5E9ED5E1B930");
  final Sp140CommandCharacteristic config = Sp140CommandCharacteristic(uuid: "45A17003-B73B-49E1-8B39-5E9ED5E1B930");

  @override
  Map<String, dynamic>? toJson() {
    return {
      "id": runtimeType.toString(),
      "version": "1.0",
      "datas": {
        "telemetry": telemetry,
      },
    };
  }

  @override
  Widget configDialog() {
    return Container();
  }

  @override
  Future onConnected(BluetoothDevice instance) async {
    await super.onConnected(instance);

    debugPrint("Device Address: ${instance.remoteId.str}");

    dd.error("BLE connected", attributes: characteristics.map((key, value) => MapEntry(key, value.keys.toList())));

    if (characteristics[SERVICE_UUID_SHORT]?[telemetry.uuid] != null) {
      debugPrint("Sp140 - setting up telemetry.");
      telemetry.setupRefreshTimer(characteristics[SERVICE_UUID_SHORT]![telemetry.uuid]!);
    }
  }

  @override
  void onDisconnected() {
    super.onDisconnected();
    telemetry.stopRefresh();
  }

  void trimToRange(DateTimeRange range) {
    telemetry.trimToRange(range);
  }
}

//-------------------------------------------------

class Sp140StatusCard extends StatelessWidget {
  final BleDeviceSp140 sp140;

  const Sp140StatusCard({super.key, required this.sp140});

  @override
  Widget build(BuildContext context) {
    return Container(
        foregroundDecoration: BoxDecoration(
            border: Border.all(width: 0.5, color: Colors.black),
            borderRadius: const BorderRadius.all(Radius.circular(15))),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                child: Container(
                    color: Colors.white38,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: StreamBuilder(
                          stream: sp140.device?.connectionState,
                          builder: (context, state) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                StreamBuilder<int>(
                                    stream: sp140.telemetry.rpm.valueRawStream,
                                    builder: (context, value) {
                                      return Text.rich(TextSpan(children: [
                                        TextSpan(
                                          text: value.data?.toString() ?? "--",
                                          style: const TextStyle(color: Colors.black, fontSize: 24),
                                        ),
                                        WidgetSpan(child: Icon(Icons.speed, color: Colors.black, size: 24)),
                                      ]));
                                    }),
                                StreamBuilder<double>(
                                    stream: sp140.telemetry.voltage.valueRawStream,
                                    builder: (context, value) {
                                      return Text.rich(TextSpan(children: [
                                        TextSpan(
                                          text: value.data != null
                                              ? "${printDouble(value: value.data!, digits: 2, decimals: 1)}v"
                                              : "?",
                                          style: const TextStyle(color: Colors.black, fontSize: 24),
                                        ),
                                        WidgetSpan(child: Icon(Icons.speed, color: Colors.black, size: 24)),
                                      ]));
                                    }),
                                StreamBuilder<double>(
                                    stream: sp140.telemetry.amps.valueRawStream,
                                    builder: (context, value) {
                                      return Text.rich(TextSpan(children: [
                                        TextSpan(
                                          text: value.data != null
                                              ? "${printDouble(value: value.data!, digits: 2, decimals: 1)}A"
                                              : "?",
                                          style: const TextStyle(color: Colors.black, fontSize: 24),
                                        ),
                                        WidgetSpan(child: Icon(Icons.speed, color: Colors.black, size: 24)),
                                      ]));
                                    }),
                              ],
                            );
                          }),
                    )))));
  }
}
