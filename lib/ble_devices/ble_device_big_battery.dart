import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:xcnav/datadog.dart' as dd;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/units.dart';

class LogStat {
  double voltMin = 100;
  double voltMax = 0;
  double chargeAh = 0;
  double accessoryAh = 0;
  double xt60Ah = 0;
  double sum = 0;

  LogStat();

  LogStat.fromListInt(List<int> data) {
    Uint8List bytes = Uint8List.fromList(data);
    voltMin = ByteData.sublistView(bytes, 0, 4).getFloat32(0, Endian.little);
    voltMax = ByteData.sublistView(bytes, 4, 8).getFloat32(0, Endian.little);
    chargeAh = ByteData.sublistView(bytes, 8, 12).getFloat32(0, Endian.little);
    accessoryAh = ByteData.sublistView(bytes, 12, 16).getFloat32(0, Endian.little);
    xt60Ah = ByteData.sublistView(bytes, 16, 20).getFloat32(0, Endian.little);
    sum = ByteData.sublistView(bytes, 20, 24).getFloat32(0, Endian.little);
  }
}

// class Telemetry {
//   LogStat live = LogStat(); // Current reading
//   LogStat session = LogStat(); // Since last power-on
//   LogStat trip = LogStat(); // Manually cleared trip counter
//   LogStat lifetime = LogStat();

//   Telemetry();
// }

class BigBatteryTelemetryCharacteristic {
  Timer? _refreshTimer;
  final String uuid;
  BluetoothCharacteristic? characteristic;

  ValueNotifier<LogStat> value = ValueNotifier(LogStat());

  BigBatteryTelemetryCharacteristic({required this.uuid});

  void stopRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer == null;
  }

  void setupRefreshTimer(BluetoothCharacteristic bleChar) {
    characteristic = bleChar;
    stopRefresh();
    _refreshTimer = Timer.periodic(Duration(seconds: 2), (_) {
      pull();
    });
  }

  Future<void> push() async {
    await characteristic?.write([0]).catchError((error) {
      dd.error("Writing Xc170 characteristic",
          errorMessage: error.toString(), errorKind: "BLE", attributes: {"char_uuid": uuid});
    });
    // Read back to verify
    await pull();
  }

  Future<void> pull() async {
    characteristic?.read().then((bytes) {
      if (bytes.length >= 24) {
        final stat = LogStat.fromListInt(bytes);
        value.value = stat;
      }
    }).catchError((error) {
      dd.error("Reading BigBattery characteristic",
          errorMessage: error.toString(), errorKind: "BLE", attributes: {"char_uuid": uuid});
    });
  }

  Map<String, dynamic>? toJson() {
    // Don't save anything in logs for now.
    return null;
  }
}

//---------------------------

class BleDeviceBigBattery extends BleDeviceHandler {
  // ignore: non_constant_identifier_names
  final SERVICE_UUID = "457d390a-3b4d-4151-810b-31261f4722c0";

  BleDeviceBigBattery() : super();

  final BigBatteryTelemetryCharacteristic live =
      BigBatteryTelemetryCharacteristic(uuid: "457d390a-0001-4a15-834e-d747633b68aa");
  final BigBatteryTelemetryCharacteristic session =
      BigBatteryTelemetryCharacteristic(uuid: "457d390a-0002-4a15-834e-d747633b68aa");
  final BigBatteryTelemetryCharacteristic trip =
      BigBatteryTelemetryCharacteristic(uuid: "457d390a-0003-4a15-834e-d747633b68aa");
  final BigBatteryTelemetryCharacteristic life =
      BigBatteryTelemetryCharacteristic(uuid: "457d390a-0004-4a15-834e-d747633b68aa");

  @override
  Map<String, dynamic>? toJson() {
    // No log for now
    return null;
    // return {
    //   "id": runtimeType.toString(),
    //   "version": "1.0",
    //   "datas": {
    //     "telemetry": telemetry,
    //   },
    // };
  }

  @override
  Widget configDialog() {
    return BigBatteryConfigDialog(bigBattery: this);
  }

  @override
  Future onConnected(BluetoothDevice instance) async {
    await super.onConnected(instance);
    if (characteristics[SERVICE_UUID]?[live.uuid] != null) {
      live.setupRefreshTimer(characteristics[SERVICE_UUID]![live.uuid]!);
    }

    session.characteristic = characteristics[SERVICE_UUID]?[session.uuid];
    trip.characteristic = characteristics[SERVICE_UUID]?[trip.uuid];
    life.characteristic = characteristics[SERVICE_UUID]?[life.uuid];
  }

  @override
  void onDisconnected() {
    super.onDisconnected();
    live.stopRefresh();
  }
}

//-------------------------------------------------

Widget makePage(String title, LogStat? stat, Function? onReset) {
  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
    Text(
      title,
      style: TextStyle(fontSize: 24),
    ),
    stat == null
        ? Container(
            height: 10,
          )
        : SizedBox(
            width: 300,
            height: 220,
            child: ListView(
              shrinkWrap: false,
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Text("Volt min/max"),
                    trailing: Text("${stat.voltMin.toStringAsFixed(2)} - ${stat.voltMax.toStringAsFixed(2)} V")),
                ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Text("Charge"),
                    trailing: Text("${printDouble(value: stat.chargeAh, digits: 6, decimals: 2)} Ah")),
                ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Text("Accessesories"),
                    trailing: Text("${printDouble(value: stat.accessoryAh, digits: 6, decimals: 2)} Ah")),
                ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Text("xt60"),
                    trailing: Text("${printDouble(value: stat.xt60Ah, digits: 6, decimals: 2)} Ah")),
                ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Text("Sum"),
                    trailing: Text("${printDouble(value: stat.sum, digits: 6, decimals: 2)} Ah")),
              ],
            ),
          ),
    if (onReset != null)
      ElevatedButton.icon(
        onPressed: () => onReset.call(),
        label: Text("Reset"),
        icon: Icon(Icons.restart_alt),
      )
  ]);
}

class BigBatteryConfigDialog extends StatelessWidget {
  final BleDeviceBigBattery bigBattery;

  const BigBatteryConfigDialog({super.key, required this.bigBattery});

  @override
  Widget build(BuildContext context) {
    final pageController = PageController();
    return AlertDialog(
        title: Text("BigBattery"),
        content: SizedBox(
          width: 300,
          height: 300,
          child: PageView(
            controller: pageController,
            children: [
              ValueListenableBuilder(
                valueListenable: bigBattery.live.value,
                builder: (context, stat, _) => makePage("Now", stat, null),
              ),
              ValueListenableBuilder(
                valueListenable: bigBattery.session.value,
                builder: (context, stat, _) {
                  return makePage("Session", stat, null);
                },
              ),
              ValueListenableBuilder(
                valueListenable: bigBattery.trip.value,
                builder: (context, stat, _) {
                  return makePage("Trip", stat, () => bigBattery.trip.push());
                },
              ),
              ValueListenableBuilder(
                valueListenable: bigBattery.life.value,
                builder: (context, stat, _) {
                  return makePage("Lifetime", stat, null);
                },
              ),
            ],
          ),
        ));
  }
}

class BigBatteryStatusCard extends StatelessWidget {
  final BleDeviceBigBattery bigBattery;

  const BigBatteryStatusCard({super.key, required this.bigBattery});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        bigBattery.session.pull().then((_) {
          bigBattery.trip.pull().then((_) {
            bigBattery.life.pull();
          });
        });
        showDialog(context: context, builder: (context) => BigBatteryConfigDialog(bigBattery: bigBattery));
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
                        padding: const EdgeInsets.all(8.0),
                        child: StreamBuilder(
                            stream: bigBattery.device?.connectionState,
                            builder: (context, state) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  ValueListenableBuilder(
                                      valueListenable: bigBattery.live.value,
                                      builder: (context, value, _) {
                                        return Text.rich(TextSpan(children: [
                                          TextSpan(
                                            text: "${printDouble(value: value.voltMin, digits: 2, decimals: 2)}v",
                                            style: const TextStyle(color: Colors.black, fontSize: 20),
                                          ),
                                          WidgetSpan(
                                              child: Icon(
                                            Icons.battery_charging_full,
                                            color: value.voltMin < 8.1 ? Colors.red : Colors.black,
                                          )),
                                        ]));
                                      }),
                                ],
                              );
                            }),
                      ))))),
    );
  }
}
