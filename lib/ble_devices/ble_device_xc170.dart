import 'dart:async';
import 'dart:ui';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/ble_devices/ble_device_value.dart';
import 'package:xcnav/datadog.dart' as dd;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

class Xc170TelemetryCharacteristic {
  Timer? _refreshTimer;
  final String uuid;
  BluetoothCharacteristic? characteristic;

  late final fuel = BleLoggedValue<double>(
      calibration: MapValue<double>([
    [24, 1], // 18 originally
    [304, 1.5],
    [556, 2],
    [797, 2.5],
    [1030, 3],
    [1265, 3.5],
    [1494, 4],
    [1722, 4.5],
    [1973, 5],
    [2210, 5.5],
    [2448, 6],
    [2688, 6.5],
    [2936, 7],
    [3193, 7.5],
    [3453, 8],
    [3732, 8.5],
    [3993, 9],
    [4274, 9.5],
    [4556, 10],
    [4830, 10.5],
    [5129, 11],
    [5433, 11.5],
    [5755, 12],
    [6101, 12.5],
    [6455, 13],
    [6837, 13.5],
    [7244, 14],
    [7544, 14.5],
    [8049, 15],
    [8180, 15.5], // 8190 originally
  ]));
  late final BleLoggedValue<int> cht;
  late final BleLoggedValue<int> egt;
  late final BleLoggedValue<int> rpm;
  late final fanAmps = BleLoggedValue<double>(
      calibration: MapValue<double>([
    [0.0, 0],
    [50000.0, 50.0]
  ]));
  late final BleLoggedValue<int> fanCtrl;

  Xc170TelemetryCharacteristic({required this.uuid});

  void stopRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer == null;
  }

  void setupRefreshTimer(BluetoothCharacteristic bleChar) {
    characteristic = bleChar;
    stopRefresh();
    _refreshTimer = Timer.periodic(Duration(seconds: 2), (_) {
      characteristic?.read().then((bytes) {
        if (bytes.length >= 12) {
          _parseData(bytes);
        }
      }).catchError((error) {
        dd.error("Reading Xc170 Telemetry characteristic",
            errorMessage: error.toString(), errorKind: "BLE", attributes: {"char_uuid": uuid});
      });
    });
  }

  /// Struct BLEDeviceXc170Telemetry {
  ///   uint16_t fuel = 0;
  ///   uint16_t CHT = 0;
  ///   uint16_t EGT = 0;
  ///   uint16_t RPM = 0;
  ///   uint16_t fanAmps = 0;  // Milliamps
  ///   uint16_t fanCtrl = 0;
  /// };
  void _parseData(List<int> bytes) {
    final time = clock.now();
    fuel.addValue((bytes[0] + (bytes[1] << 8)).toDouble(), time);
    cht.addValue(bytes[2] + (bytes[3] << 8), time);
    egt.addValue(bytes[4] + (bytes[5] << 8), time);
    rpm.addValue(bytes[6] + (bytes[7] << 8), time);
    fanAmps.addValue((bytes[8] + (bytes[9] << 8)).toDouble(), time);
    fanCtrl.addValue(bytes[10] + (bytes[11] << 8), time);
  }

  Map<String, dynamic>? toJson() {
    return {
      "fuel": fuel,
      "cht": cht,
      "egt": egt,
      "rpm": rpm,
      "fanAmps": fanAmps,
    };
  }
}

//---------------------------

class Xc170FanControlCharacteristic {
  final String uuid;
  BluetoothCharacteristic? characteristic;

  int _override = 0;
  int _chtMin = 0;
  int _chtMax = 0;

  Xc170FanControlCharacteristic({required this.uuid});

  Future<int> getOverride() async {
    await pull();
    return _override;
  }

  Future<int> getChtMin() async {
    await pull();
    return _chtMin;
  }

  Future<int> getChtMax() async {
    await pull();
    return _chtMax;
  }

  Future<void> setOverride(int value) {
    _override = value;
    return push();
  }

  Future<void> setChtMin(int value) {
    _chtMin = value;
    return push();
  }

  Future<void> setChtMax(int value) {
    _chtMax = value;
    return push();
  }

  Future<void> push() async {
    await characteristic?.write(_packData()).catchError((error) {
      dd.error("Writing Xc170 FanControl characteristic",
          errorMessage: error.toString(), errorKind: "BLE", attributes: {"char_uuid": uuid});
    });
    // Read back to verify
    await pull();
  }

  Future<void> pull() async {
    List<int>? bytes = await characteristic?.read().catchError((error) {
      dd.error("Reading Xc170 FanControl characteristic",
          errorMessage: error.toString(), errorKind: "BLE", attributes: {"char_uuid": uuid});
      return <int>[];
    });
    if (bytes != null && bytes.length >= 6) {
      _parseData(bytes);
    }
  }

  /// Struct BLEDeviceXc170FanControl {
  ///   uint16_t override = 0;
  ///   uint16_t chtMin = 210;
  ///   uint16_t chtMax = 230;
  /// };
  void _parseData(List<int> bytes) {
    _override = bytes[0] + (bytes[1] << 8);
    _chtMin = bytes[2] + (bytes[3] << 8);
    _chtMax = bytes[4] + (bytes[5] << 8);
  }

  List<int> _packData() {
    return [_override & 0xff, _override >> 8, _chtMin & 0xff, _chtMin >> 8, _chtMax & 0xff, _chtMax >> 8];
  }
}

//---------------------------

class BleDeviceXc170 extends BleDeviceHandler {
  // ignore: non_constant_identifier_names
  final SERVICE_UUID = "e1e7af55-0c37-4f29-80bf-f447757738b0";

  BleDeviceXc170() : super();

  final Xc170TelemetryCharacteristic telemetry =
      Xc170TelemetryCharacteristic(uuid: "e1e7af55-9460-40f3-8b57-af0e56b471c3");
  final Xc170FanControlCharacteristic fanControl =
      Xc170FanControlCharacteristic(uuid: "e1e7af55-6eb0-40a7-bd9e-496d6b874940");

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
  Future onConnected(BluetoothDevice instance) async {
    await super.onConnected(instance);
    if (characteristics[SERVICE_UUID]?[telemetry.uuid] != null) {
      telemetry.setupRefreshTimer(characteristics[SERVICE_UUID]![telemetry.uuid]!);
    }
    if (characteristics[SERVICE_UUID]?[fanControl.uuid] != null) {
      fanControl.characteristic = characteristics[SERVICE_UUID]![fanControl.uuid];
      fanControl.pull();
    }
  }

  @override
  void onDisconnected() {
    super.onDisconnected();
    telemetry.stopRefresh();
  }
}

//-------------------------------------------------

class Xc170ConfigDialog extends StatelessWidget {
  final BleDeviceXc170 xc170;

  const Xc170ConfigDialog({super.key, required this.xc170});

  @override
  Widget build(BuildContext context) {
    // Note: using stale state here...
    double override = xc170.fanControl._override.toDouble();
    final chtMinController = TextEditingController(text: xc170.fanControl._chtMin.toString());
    final chtMaxController = TextEditingController(text: xc170.fanControl._chtMax.toString());
    return AlertDialog(
      title: Text("Xc170 Ble Device Config"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Form(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 40,
              child: TextFormField(
                controller: chtMinController,
                keyboardType: TextInputType.number,
                validator: (text) {
                  final value = parseAsInt(text);
                  if (value == null) {
                    return "Must be a number";
                  }
                  if (value < 0) {
                    return "Must be at least 0";
                  }
                  if (value > 1000) {
                    return "Should not be more than 1000";
                  }
                  return null;
                },
                onEditingComplete: () {
                  final value = parseAsInt(chtMinController.text);
                  if (value != null) {
                    xc170.fanControl.setChtMin(value);
                  }
                },
              ),
            ),
            SizedBox(
              width: 10,
              child: Divider(),
            ),
            SizedBox(
              width: 40,
              child: TextFormField(
                controller: chtMaxController,
                keyboardType: TextInputType.number,
                validator: (text) {
                  final value = parseAsInt(text);
                  if (value == null) {
                    return "Must be a number";
                  }
                  if (value < 0) {
                    return "Must be at least 0";
                  }
                  if (value > 2000) {
                    return "Should not be more than 2000";
                  }
                  return "";
                },
                onEditingComplete: () {
                  final value = parseAsInt(chtMaxController.text);
                  if (value != null) {
                    xc170.fanControl.setChtMax(value);
                  }
                },
              ),
            )
          ])),
          SizedBox(
              width: 40,
              height: 30,
              child: StatefulBuilder(builder: (context, setState) {
                return Slider(
                  max: 180,
                  value: override,
                  onChanged: (value) {
                    setState(() {
                      override = value;
                    });
                  },
                  onChangeEnd: (value) {
                    setState(() {
                      xc170.fanControl.setOverride(value.round());
                    });
                  },
                );
              })),
        ],
      ),
    );
  }
}

class Xc170StatusCard extends StatelessWidget {
  final BleDeviceXc170 xc170;

  const Xc170StatusCard({super.key, required this.xc170});

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
                      padding: const EdgeInsets.all(8.0),
                      child: StreamBuilder(
                          stream: xc170.device?.connectionState,
                          builder: (context, state) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                ElevatedButton.icon(
                                  icon: Icon(Icons.wind_power),
                                  label: Text("Set"),
                                  onPressed: () async {
                                    if (context.mounted) {
                                      showDialog(
                                          context: context, builder: (context) => Xc170ConfigDialog(xc170: xc170));
                                    }
                                  },
                                ),
                                StreamBuilder(
                                    stream: xc170.telemetry.fuel.valueRawStream,
                                    builder: (context, value) => Text.rich(TextSpan(children: [
                                          TextSpan(
                                            text: printDouble(
                                              value: value.data ?? 0,
                                              digits: 4,
                                              decimals: 0,
                                            ),
                                            style: const TextStyle(color: Colors.black, fontSize: 30),
                                          ),
                                          WidgetSpan(
                                              child: Icon(
                                            Icons.speed,
                                            color: Colors.black,
                                          )),
                                        ]))),
                                StreamBuilder(
                                    stream: xc170.telemetry.cht.valueRawStream,
                                    builder: (context, value) => Text.rich(
                                        TextSpan(children: [
                                          TextSpan(
                                            text: value.data.toString(),
                                            style: const TextStyle(fontSize: 30),
                                          ),
                                          WidgetSpan(
                                              child: Icon(
                                            Icons.thermostat,
                                            color: Colors.black,
                                          )),
                                          TextSpan(text: "CHT ", style: const TextStyle(fontSize: 20)),
                                        ]),
                                        style: TextStyle(color: (value.data ?? 0) > 230 ? Colors.red : Colors.black))),
                                StreamBuilder(
                                    stream: xc170.telemetry.egt.valueRawStream,
                                    builder: (context, value) => Text.rich(
                                        TextSpan(children: [
                                          TextSpan(
                                            text: value.data.toString(),
                                            style: TextStyle(fontSize: 30),
                                          ),
                                          WidgetSpan(
                                              child: Icon(
                                            Icons.thermostat,
                                            color: Colors.black,
                                          )),
                                          TextSpan(text: "EGT ", style: TextStyle(fontSize: 20)),
                                        ]),
                                        style: TextStyle(color: (value.data ?? 0) > 600 ? Colors.red : Colors.black))),
                                StreamBuilder(
                                    stream: xc170.telemetry.fanAmps.valueRawStream,
                                    builder: (context, value) => Text.rich(
                                          TextSpan(children: [
                                            TextSpan(
                                              text: printDouble(
                                                value: value.data ?? 0,
                                                digits: 2,
                                                decimals: 1,
                                              ),
                                              style: const TextStyle(fontSize: 30),
                                            ),
                                            TextSpan(
                                                text: "A", style: const TextStyle(color: Colors.black, fontSize: 20)),
                                            WidgetSpan(
                                                child: Icon(
                                              Icons.wind_power,
                                              color: Colors.black,
                                            )),
                                          ]),
                                          style: TextStyle(color: Colors.black),
                                        )),
                                StreamBuilder(
                                    stream: xc170.telemetry.fuel.valueRawStream,
                                    builder: (context, value) => value.data == null
                                        ? Text("?")
                                        : Text.rich(TextSpan(children: [
                                            WidgetSpan(
                                                child: Icon(
                                              state.data == BluetoothConnectionState.connected
                                                  ? Icons.bluetooth_connected
                                                  : Icons.bluetooth_disabled,
                                              size: 30,
                                              color: state.data == BluetoothConnectionState.connected
                                                  ? Colors.blue
                                                  : Colors.grey.shade800,
                                            )),
                                            if (value.data! >= xc170.telemetry.fuel.calibration!.maxValue)
                                              TextSpan(text: ">", style: TextStyle(fontSize: 30, color: Colors.green)),
                                            if (value.data! <= xc170.telemetry.fuel.calibration!.minValue)
                                              TextSpan(text: "<", style: TextStyle(fontSize: 30, color: Colors.red)),
                                            richValue(UnitType.fuel, value.data ?? 0,
                                                digits: 2,
                                                decimals: 1,
                                                removeZeros: false,
                                                valueStyle: const TextStyle(color: Colors.black, fontSize: 30),
                                                unitStyle: TextStyle(color: Colors.grey.shade700, fontSize: 20)),
                                          ]))),
                              ],
                            );
                          }),
                    )))));
  }
}
