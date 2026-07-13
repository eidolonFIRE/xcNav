import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/ble_devices/ble_device_value.dart';
import 'package:xcnav/datadog.dart' as dd;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/tts_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/util.dart';

class BleFastLinkTelemetry {
  static const int bmsCellsNum = 24;
  static const int tempSensorCount = 8;

  // Protocol version (3)
  int version = 0;
  // Sequential packet ID for drop detection
  int packetId = 0;
  // Time since boot (ms)
  int uptimeMs = 0;

  // Controller Data
  // Barometric altitude (cm, x100 from meters)
  int altitudeCm = 0;
  // Barometric sensor temperature (deci-C, x10)
  int baroTempDC = 0;
  // Barometric pressure (deci-hPa, x10)
  int baroPressureDHPa = 0;
  // Vertical speed (cm/s, x100 from m/s)
  int varioCmps = 0;
  // ESP32 internal temperature (deci-C, x10)
  int mcuTempDC = 0;
  // Raw throttle potentiometer (0..4095)
  int potRaw = 0;
  // 0=DISARMED, 1=ARMED, 2=ARMED_CRUISING
  int deviceState = 0;

  // ESC Data
  // TelemetryState enum
  int escStatus = 0;
  // ESC Voltage (deci-Volts, x10)
  int escVoltsDV = 0;
  // DC bus current (deci-Amps, x10)
  int escAmpsDA = 0;
  // AC phase current (deci-Amps, x10)
  int escPhaseCurrentDA = 0;
  // Electrical RPM
  int escRpm = 0;
  // MOSFET Temp (deci-C, x10)
  int escTempMosDC = 0;
  // Capacitor Temp (deci-C, x10)
  int escTempCapDC = 0;
  // MCU Temp (deci-C, x10)
  int escTempMcuDC = 0;
  // Motor Temp (deci-C, x10), INT16_MIN = no sensor
  int escTempMotorDC = 0;
  // Input PWM command (recv_pwm, native units)
  int escInPWM = 0;
  // Commutation PWM output (comm_pwm, raw)
  int escOutPWM = 0;
  // Voltage modulation index (raw)
  int escVModulation = 0;
  // Runtime error bitmask
  int escError = 0;
  // Self-check error bitmask
  int escSelfcheck = 0;
  // ESC static hardware info
  int escHardwareId = 0;
  int escFwVersion = 0;
  int escBootloaderVersion = 0;
  // ESC internal runtime (ms) from time_10ms x 10
  int escRuntimeMs = 0;
  // ESC serial number (16 bytes)
  List<int> escSnCode = List<int>.filled(16, 0);

  // BMS Data
  // TelemetryState enum
  int bmsStatus = 0;
  // State of Charge (%, 0-100, native 1% resolution)
  int bmsSoc = 0;
  // Total Battery Voltage (deci-Volts, x10)
  int bmsVoltsDV = 0;
  // Battery Current (deci-Amps, x10)
  int bmsAmpsDA = 0;
  // Energy per cycle (mAh, native 1 mAh resolution)
  int bmsEnergyCycleMAh = 0;
  // Battery cycle count
  int bmsBatteryCycle = 0;
  // Battery failure status
  int bmsFailLevel = 0;
  // Charging state (0/1)
  int bmsIsCharging = 0;
  // Charge MOSFET state (0/1)
  int bmsIsChargeMos = 0;
  // Discharge MOSFET state (0/1)
  int bmsIsDischargeMos = 0;
  // Charge wire physically connected (0/1)
  int bmsChargeWire = 0;
  // Low SOC warning active (0/1)
  int bmsLowSocWarning = 0;
  // Battery ready for use (0/1)
  int bmsBatteryReady = 0;
  // Highest temperature (C, native 1C resolution)
  int bmsHighestTempC = 0;
  // Lowest temperature (C, native 1C resolution)
  int bmsLowestTempC = 0;
  // Highest cell voltage (mV, native 1 mV resolution)
  int bmsCellMaxMV = 0;
  // Lowest cell voltage (mV, native 1 mV resolution)
  int bmsCellMinMV = 0;
  // Cell voltage differential (mV)
  int bmsVoltageDiffMV = 0;
  // Battery serial/ID string (null-terminated)
  String bmsBatteryId = '';
  // BMS type (0=unknown, 1=Type A older, 2=Type B newer)
  int bmsType = 0;

  // Extended BMS arrays (compressed)
  // 24 cell voltages (mV, native resolution)
  List<int> bmsCellVoltagesMV = List<int>.filled(bmsCellsNum, 0);
  // 8 temps (C, MOS/BAL/T1-T4/unused/unused)
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

  final power = BleLoggedValue<double>();
  final charge = BleLoggedValue<int>();
  ValueNotifier<int> diffVolt = ValueNotifier<int>(0);
  ValueNotifier<int> state = ValueNotifier<int>(0);

  Sp140TelemetryCharacteristic({required this.uuid});

  DateTime? _audioDiffAlerted;

  void stopRefresh() {
    _listener?.cancel();
    _listener = null;
  }

  void setupRefreshTimer(BluetoothCharacteristic bleChar) {
    characteristic = bleChar;
    stopRefresh();

    characteristic?.setNotifyValue(true);
    _listener = characteristic?.onValueReceived.listen((data) {
      if (data.isNotEmpty) {
        final now = clock.now();
        final telemetry = BleFastLinkTelemetry.fromListInt(data);
        power.addValue(
            (telemetry.bmsAmpsDA.toDouble() / 10.0) * (telemetry.bmsVoltsDV.toDouble() / 10.0) / 1000.0, now);
        diffVolt.value = telemetry.bmsVoltageDiffMV;
        charge.addValue(telemetry.bmsSoc, now);
        state.value = telemetry.deviceState;

        // Audio alert for battery voltage difference
        if ((_audioDiffAlerted?.isBefore(clock.now().subtract(Duration(minutes: 2))) ?? true) && diffVolt.value > 200) {
          _audioDiffAlerted = now;
          if (diffVolt.value > 400) {
            ttsService.speak(AudioMessage("Critical battery balance!", priority: 1, volume: 1.0));
          } else {
            ttsService.speak(AudioMessage("Check battery balance!", priority: 2, volume: 1.0));
          }
        }

        // Update myTelemetry fuel reports
        if (myTelemetry.inFlight) {
          if (myTelemetry.fuelReports.isEmpty ||
              myTelemetry.fuelReports.last.time
                  .isBefore(now.subtract(Duration(minutes: settingsMgr.sp140FuelSaveIntervalMin.value)))) {
            myTelemetry.insertFuelReport(
              now,
              telemetry.bmsSoc.toDouble(),
              tolerance: const Duration(seconds: 30),
            );
          }
        }
      }
    });
  }

  Map<String, dynamic>? toJson() {
    return {
      "charge": charge,
      "power": power,
    };
  }

  void trimToRange(DateTimeRange range) {
    charge.compress(epsilon: 0.05);
    charge.trimToRange(range);
    power.compress();
    power.trimToRange(range);
  }
}

// class Sp140CommandCharacteristic {
//   final String uuid;
//   BluetoothCharacteristic? characteristic;
//   StreamSubscription<List<int>>? _listener;

//   Sp140CommandCharacteristic({required this.uuid});

//   void stopRefresh() {
//     _listener?.cancel();
//     _listener = null;
//   }

//   void setupRefreshTimer(BluetoothCharacteristic bleChar) {
//     characteristic = bleChar;
//     stopRefresh();
//   }

//   Future<void> push(List<int> data) async {
//     debugPrint("RunLeader: Pushing Config ${data.map((e) => e.toRadixString(16)).toList()}");
//     await characteristic?.write(data).catchError((error) {
//       dd.error("Writing config characteristic",
//           errorMessage: error.toString(), errorKind: "BLE", attributes: {"char_uuid": uuid});
//     });
//   }

//   Map<String, dynamic>? toJson() {
//     // Config saves nothing
//     return null;
//   }
// }

//---------------------------

class BleDeviceSp140 extends BleDeviceHandler {
  @override
  // ignore: overridden_fields, non_constant_identifier_names
  final SERVICE_UUID = "45a17001-b73b-49e1-8b39-5e9ed5e1b930";

  BleDeviceSp140() : super();

  final Sp140TelemetryCharacteristic telemetry =
      Sp140TelemetryCharacteristic(uuid: "45a17002-b73b-49e1-8b39-5e9ed5e1b930");
  // final Sp140CommandCharacteristic config = Sp140CommandCharacteristic(uuid: "45a17003-b73b-49e1-8b39-5e9ed5e1b930");

  bool? isArmed() {
    if (device?.isConnected ?? false) {
      // Connected and armed
      return telemetry.state.value > 0;
    } else {
      return null;
    }
  }

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

    // Override fuel unit settings so the fuel reports make sense
    settingsMgr.displayUnitFuel.value = DisplayUnitsFuel.percent;

    debugPrint("Device Address: ${instance.remoteId.str}");
    if (characteristics[SERVICE_UUID]?[telemetry.uuid] != null) {
      debugPrint("Sp140 - setting up telemetry.");
      telemetry.setupRefreshTimer(characteristics[SERVICE_UUID]![telemetry.uuid]!);
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

class Sp140ConfigDialog extends StatelessWidget {
  final BleDeviceSp140 sp140;

  const Sp140ConfigDialog({super.key, required this.sp140});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("SP140 Ble Device Config"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Fuel Save Interval (minutes)"),
          ValueListenableBuilder<int>(
              valueListenable: settingsMgr.sp140FuelSaveIntervalMin.listenable,
              builder: (context, value, child) {
                return Slider(
                  value: value.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 10,
                  label: "$value min",
                  onChanged: (newValue) {
                    settingsMgr.sp140FuelSaveIntervalMin.value = newValue.round();
                  },
                );
              }),
        ],
      ),
    );
  }
}

//-------------------------------------------------

class Sp140StatusCard extends StatelessWidget {
  final BleDeviceSp140 sp140;

  const Sp140StatusCard({super.key, required this.sp140});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showDialog(
            context: context,
            builder: (context) {
              return Sp140ConfigDialog(sp140: sp140);
            });
      },
      child: Container(
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
                              final color =
                                  state.data == BluetoothConnectionState.disconnected ? Colors.grey : Colors.black;
                              return DefaultTextStyle.merge(
                                style: TextStyle(color: color),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    StreamBuilder<double>(
                                        stream: sp140.telemetry.power.valueRawStream,
                                        builder: (context, value) {
                                          return Text.rich(TextSpan(children: [
                                            TextSpan(
                                              text: value.data != null ? value.data!.toStringAsFixed(1) : "?",
                                              style: const TextStyle(fontSize: 24),
                                            ),
                                            TextSpan(
                                              text: "kW",
                                              style: TextStyle(fontSize: 14),
                                            ),
                                            WidgetSpan(child: Icon(Icons.electric_bolt, color: color, size: 24)),
                                          ]));
                                        }),
                                    StreamBuilder<int>(
                                        stream: sp140.telemetry.charge.valueRawStream,
                                        builder: (context, value) {
                                          return Text.rich(TextSpan(children: [
                                            TextSpan(
                                              text: value.data != null ? "${value.data}" : "?",
                                              style: TextStyle(fontSize: 24),
                                            ),
                                            TextSpan(
                                              text: "%",
                                              style: TextStyle(fontSize: 14),
                                            ),
                                            WidgetSpan(child: batteryIcon(value.data?.toDouble() ?? 0, 24)),
                                          ]));
                                        }),
                                    if (myTelemetry.inFlight && myTelemetry.sumFuelStat != null)
                                      StreamBuilder<int>(
                                          stream: sp140.telemetry.charge.valueRawStream,
                                          builder: (context, value) {
                                            final etaEmpty = myTelemetry.sumFuelStat!
                                                .extrapolateEndurance(myTelemetry.fuelReports.last, from: clock.now());

                                            final warn = etaEmpty < const Duration(minutes: 15);
                                            final style = TextStyle(
                                                color: warn ? Colors.red : null,
                                                fontSize: 24,
                                                fontWeight: warn ? FontWeight.bold : FontWeight.normal);
                                            return Text.rich(TextSpan(children: [
                                              richHrMin(
                                                  duration: etaEmpty,
                                                  valueStyle: style,
                                                  unitStyle: style.copyWith(fontSize: 14)),
                                              WidgetSpan(child: Icon(Icons.timer_outlined, size: 24, color: color))
                                            ]));
                                          }),
                                    ValueListenableBuilder<int>(
                                        valueListenable: sp140.telemetry.diffVolt,
                                        builder: (context, value, _) {
                                          if (value > 20) {
                                            return Text.rich(TextSpan(children: [
                                              TextSpan(
                                                text: "$value",
                                                style: TextStyle(fontSize: 24),
                                              ),
                                              TextSpan(
                                                text: "mV",
                                                style: TextStyle(fontSize: 14),
                                              ),
                                              WidgetSpan(
                                                  child: Icon(Icons.battery_alert,
                                                      color: value > 200 ? Colors.red : color, size: 24)),
                                            ]));
                                          } else {
                                            return Container();
                                          }
                                        }),
                                  ],
                                ),
                              );
                            }),
                      ))))),
    );
  }
}
