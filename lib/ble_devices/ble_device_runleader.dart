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

class RunleaderTelemetryCharacteristic {
  final String uuid;
  BluetoothCharacteristic? characteristic;
  StreamSubscription<List<int>>? _listener;

  final rpm = BleLoggedValue<int>();

  RunleaderTelemetryCharacteristic({required this.uuid});

  static List<int> keyFromMac(String mac) {
    final parts = mac.split(":").map((e) => int.parse(e, radix: 16)).toList();
    return parts.reversed.toList();
  }

  void stopRefresh() {
    _listener?.cancel();
    _listener = null;
  }

  void setupRefreshTimer(BluetoothCharacteristic bleChar) {
    characteristic = bleChar;
    stopRefresh();

    characteristic?.setNotifyValue(true);
    _listener = characteristic?.onValueReceived.listen((data) {
      if (data.length == 13 && data[0] == 0xa7 && data[1] == 0x00 && data[2] == 0x1f && data[3] == 0x07) {
        final mac = keyFromMac(characteristic?.device.remoteId.str ?? "00:00:00:00:00:00");
        final parsed = mcuTea([0x00, 0x1f], mac, data.sublist(4, 13));
        int value = (parsed[4] << 8) + parsed[3];
        rpm.addValue(value, clock.now());
      }
    });
  }

  List<int> mcuTea(List<int> cid, List<int> mac, List<int> data) {
    if (cid[0] == 0) {
      cid[0] = 1;
      if (cid[1] == 0) {
        cid[1] = 1;
      }
    } else if (cid[1] == 0) {
      cid[1] = 1;
    }

    for (int i = 0; i < data.length; i++) {
      int macIdx = i - 3 * ((i ~/ 3) & 0xFFFFFFFE);
      data[i] = cid[i & 1] ^ (mac[macIdx] ^ data[i]);
    }

    return data;
  }

  Future<void> pull() async {
    characteristic?.read().then((bytes) {
      if (bytes.length > 1) {
        int value = bytes[0] + bytes[1] << 8;
        rpm.addValue(value, clock.now());
      }
    }).catchError((error) {
      dd.error("Reading Runleader characteristic",
          errorMessage: error.toString(), errorKind: "BLE", attributes: {"char_uuid": uuid});
    });
  }

  Map<String, dynamic>? toJson() {
    return {
      "rpm": rpm,
    };
  }
}

class RunleaderConfigCharacteristic {
  final String uuid;
  BluetoothCharacteristic? characteristic;
  StreamSubscription<List<int>>? _listener;

  final int _mask = 0xFFFFFFFF;
  final int _initV7 = ((-1640531527) & 0xFFFFFFFF); // 2654435769

  RunleaderConfigCharacteristic({required this.uuid});

  void stopRefresh() {
    _listener?.cancel();
    _listener = null;
  }

  void setupRefreshTimer(BluetoothCharacteristic bleChar) {
    characteristic = bleChar;
    stopRefresh();

    characteristic?.setNotifyValue(true);
    _listener = characteristic?.onValueReceived.listen((data) {
      debugPrint("Runleader - Config received: ${data.map((e) => e.toRadixString(16)).toList()}");
      if (data[0] == 0xa6 && data[1] == 0x11 && data[2] == 0x23) {
        debugPrint("RunLeader - Got handshake challenge, responding...");
        // Process handshake and respond
        final payload = data.sublist(3, 19);
        final response = [0x11, 0x24] + tea(payload);
        final checksum = response.reduce((a, b) => a + b) % 256;
        final msg = [0xa6] + response + [checksum];
        push([0xa6, 0x01, 0x0e, 0x0f, 0x6a]);
        Timer(Duration(milliseconds: 100), () {
          push(msg);
        });
      }
    });
  }

  List<int> tea(List<int> data) {
    final bytes = Uint8List.fromList(data);
    final byteData = ByteData.sublistView(bytes);

    int v9 = byteData.getUint32(0, Endian.little);
    int v10 = byteData.getUint32(4, Endian.little);
    int v14 = byteData.getUint32(8, Endian.little);
    int v11 = byteData.getUint32(12, Endian.little);
    int v12 = _initV7;
    int v13 = _initV7;

    for (int i = 0; i < 32; i++) {
      v9 = (v9 + (((v10 << 4) + 1097419881) ^ (v10 + v12) ^ ((v10 >> 5) + 1852538888))) & _mask;
      v10 = (v10 + (((v9 << 4) + 1640178394) ^ (v12 + v9) ^ ((v9 >> 5) + 507539989))) & _mask;
      v12 = (v12 - 1640531527) & _mask;
    }

    final int v20 = v9;

    for (int i = 0; i < 32; i++) {
      v14 = (v14 + (((v11 << 4) + 1097419881) ^ (v11 + v13) ^ ((v11 >> 5) + 1852538888))) & _mask;
      v11 = (v11 + (((v14 << 4) + 1640178394) ^ (v13 + v14) ^ ((v14 >> 5) + 507539989))) & _mask;
      v13 = (v13 - 1640531527) & _mask;
    }

    byteData.setUint32(0, v20, Endian.little);
    byteData.setUint32(4, v10, Endian.little);
    byteData.setUint32(8, v14, Endian.little);
    byteData.setUint32(12, v11, Endian.little);

    return bytes.toList();
  }

  Future<void> push(List<int> data) async {
    debugPrint("RunLeader: Pushing Config ${data.map((e) => e.toRadixString(16)).toList()}");
    await characteristic?.write(data).catchError((error) {
      dd.error("Writing config characteristic",
          errorMessage: error.toString(), errorKind: "BLE", attributes: {"char_uuid": uuid});
    });
    // Read back to verify
    // await pull();
  }

  Future<void> pull() async {
    characteristic?.read().then((bytes) {
      if (bytes.length > 1) {
        debugPrint("Runleader - Config pulled: ${bytes.toList()}");
      }
    }).catchError((error) {
      dd.error("Reading Runleader characteristic",
          errorMessage: error.toString(), errorKind: "BLE", attributes: {"char_uuid": uuid});
    });
  }

  Map<String, dynamic>? toJson() {
    // Config saves nothing
    return null;
  }
}

//---------------------------

class BleDeviceRunleader extends BleDeviceHandler {
  @override
  // ignore: overridden_fields, non_constant_identifier_names
  final SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb";
  // ignore: non_constant_identifier_names
  final SERVICE_UUID_SHORT = "ffe0";

  BleDeviceRunleader() : super();

  final RunleaderTelemetryCharacteristic telemetry =
      RunleaderTelemetryCharacteristic(uuid: "ffe2"); //"0000ffe2-0000-1000-8000-00805f9b34fb");
  final RunleaderConfigCharacteristic config =
      RunleaderConfigCharacteristic(uuid: "ffe3"); //"0000ffe3-0000-1000-8000-00805f9b34fb");

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

    if (characteristics[SERVICE_UUID_SHORT]?[telemetry.uuid] != null) {
      debugPrint("Runleader - setting up telemetry.");
      telemetry.setupRefreshTimer(characteristics[SERVICE_UUID_SHORT]![telemetry.uuid]!);
    }
    if (characteristics[SERVICE_UUID_SHORT]?[config.uuid] != null) {
      debugPrint("Runleader - setting up config.");
      config.setupRefreshTimer(characteristics[SERVICE_UUID_SHORT]![config.uuid]!);

      // Send a handshake
      config.push(hex.decode("a6112380df8a291caa5b5abf02318c4b4b75ed37"));
    }
  }

  @override
  void onDisconnected() {
    super.onDisconnected();
    telemetry.stopRefresh();
  }
}

//-------------------------------------------------

class RunleaderStatusCard extends StatelessWidget {
  final BleDeviceRunleader runleader;

  const RunleaderStatusCard({super.key, required this.runleader});

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
                          stream: runleader.device?.connectionState,
                          builder: (context, state) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                StreamBuilder<int>(
                                    stream: runleader.telemetry.rpm.valueRawStream,
                                    builder: (context, value) {
                                      return Text.rich(TextSpan(children: [
                                        TextSpan(
                                          text: value.data?.toString() ?? "--",
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
