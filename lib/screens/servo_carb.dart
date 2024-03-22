import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:xcnav/servo_carb_service.dart';
import 'package:xcnav/widgets/carb_needle_dial.dart';

class ServoCarb extends StatefulWidget {
  const ServoCarb({Key? key}) : super(key: key);

  @override
  State<ServoCarb> createState() => _ServoCarbState();
}

class _ServoCarbState extends State<ServoCarb> {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(
            "ServoCarb",
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          actions: [
            IconButton(
                onPressed: () {
                  Navigator.pushNamed(context, "/bleScan");
                },
                icon: Icon(
                  _adapterState == BluetoothAdapterState.on
                      ? (servoCarbDevice != null ? Icons.bluetooth_connected : Icons.bluetooth)
                      : Icons.bluetooth_disabled,
                  color: _adapterState == BluetoothAdapterState.on
                      ? (servoCarbDevice != null ? Colors.lightBlue : Colors.white)
                      : Colors.red,
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
                    children: highNeedle.config.presets.keys
                        .map((e) => ElevatedButton(
                            onLongPress: () {
                              debugPrint("Save preset: $e");
                              setState(() {
                                highNeedle.config.setPreset(e, highNeedle.mixture);
                                lowNeedle.config.setPreset(e, lowNeedle.mixture);
                              });
                            },
                            onPressed: () {
                              highNeedle.loadPreset(e);
                              lowNeedle.loadPreset(e);
                            },
                            child: Text(e)))
                        .toList(),
                  ),
                ],
              ),

              // ==============================================
              CarbNeedleDial(highNeedle, MediaQuery.of(context).size.width * 0.4, label: "H"),
              CarbNeedleDial(lowNeedle, MediaQuery.of(context).size.width * 0.4, label: "L"),
            ],
          ),
        ));
  }
}
