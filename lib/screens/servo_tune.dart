import 'dart:async';
import 'dart:math';

import 'package:dart_numerics/dart_numerics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:xcnav/models/carb_needle.dart';

import 'package:xcnav/servo_carb_service.dart';
import 'package:xcnav/widgets/carb_needle_dial.dart';

class ServoTune extends StatefulWidget {
  const ServoTune({Key? key}) : super(key: key);

  @override
  State<ServoTune> createState() => _ServoTuneState();
}

class _ServoTuneState extends State<ServoTune> {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;

  CarbNeedle highNeedle = CarbNeedle(uuid: "ff01", dof: 160 / 180 * pi);
  CarbNeedle lowNeedle = CarbNeedle(uuid: "ff02", dof: 160 / 180 * pi);

  @override
  void initState() {
    super.initState();

    _adapterStateStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _adapterStateStateSubscription.cancel();
    super.dispose();
  }

  void txNeedle(CarbNeedle needle) {
    if (servoCarbDevice != null) {
      // debugPrint("device");
      // write!
      final service = servoCarbDevice!.servicesList
          .where((element) => element.uuid.str == "00ff") // 0x00ff
          .firstOrNull;
      if (service != null) {
        // debugPrint("service");
        final intValue = needle.servoPWM;
        final characteristic = service.characteristics.where((element) => element.uuid.str == needle.uuid).firstOrNull;
        if (characteristic != null) {
          // debugPrint("Write $intValue");
          characteristic.write([intValue & 0xff, (intValue >> 8) & 0xff]);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(
            "Tune",
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          actions: [
            IconButton(
                onPressed: () {
                  Navigator.pushNamed(context, "/bleScan");
                },
                icon: Icon(
                  servoCarbDevice != null ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: servoCarbDevice != null ? Colors.blueAccent : Colors.white,
                ))
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Load Preset",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Text(
                    "( long press to save )",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Container(
                    height: 20,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: highNeedle.presets.keys
                        .map((e) => ElevatedButton(
                            onLongPress: () {
                              debugPrint("Save preset: $e");
                              setState(() {
                                highNeedle.presets[e] = highNeedle.mixture;
                                lowNeedle.presets[e] = lowNeedle.mixture;
                              });
                            },
                            onPressed: () {
                              // TODO: safety
                              highNeedle.mixture = highNeedle.presets[e]!;
                              txNeedle(highNeedle);
                              lowNeedle.mixture = lowNeedle.presets[e]!;
                              txNeedle(lowNeedle);
                            },
                            child: Text(e)))
                        .toList(),
                  ),
                  // SwitchListTile(title: Text("Cruise after 5 min."), value: false, onChanged: (_) {}),
                ],
              ),

              // ==============================================
              CarbNeedleDial(highNeedle, MediaQuery.of(context).size.width * 0.4, onUp: () {
                txNeedle(highNeedle);
              },
                  label: const Text(
                    "H",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 40,
                        color: Colors.black,
                        shadows: [BoxShadow(color: Colors.white, blurRadius: 30)]),
                  ),
                  labels: highNeedle.presets
                      .map((key, value) => MapEntry(key, CarbNeedleDialLabel(label: Text(key), mixture: value)))
                      .values
                      .toList()),

              // ==============================================
              CarbNeedleDial(lowNeedle, MediaQuery.of(context).size.width * 0.4, onUp: () {
                txNeedle(lowNeedle);
              },
                  label: const Text(
                    "L",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 40,
                        color: Colors.black,
                        shadows: [BoxShadow(color: Colors.white, blurRadius: 30)]),
                  ),
                  labels: lowNeedle.presets
                      .map((key, value) => MapEntry(key, CarbNeedleDialLabel(label: Text(key), mixture: value)))
                      .values
                      .toList()),
            ],
          ),
        ));
  }
}
