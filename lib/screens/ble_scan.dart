import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:xcnav/servo_carb_service.dart';
import 'package:xcnav/widgets/scan_result_tile.dart';
import 'package:xcnav/snackbar.dart';
import 'package:xcnav/widgets/system_device_tile.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final List<BluetoothDevice> _systemDevices = [];
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  @override
  void initState() {
    super.initState();

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      _scanResults = results;
      if (mounted) {
        setState(() {});
      }
    }, onError: (e) {
      debugPrint(e);
      debugPrint(e);
      // SnackBar(ABC.b, prettyException("Scan Error:", e), success: false);
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      _isScanning = state;
      if (mounted) {
        setState(() {});
      }
    });

    // auto start a scan
    onScanPressed();
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    super.dispose();
  }

  Future onScanPressed() async {
    try {
      // TODO: fix ble
      // _systemDevices = await FlutterBluePlus.systemDevices();
    } catch (e) {
      SnackbarTools.show(ABC.b, prettyException("System Devices Error:", e), success: false);
    }
    try {
      // android is slow when asking for all advertisements,
      // so instead we only ask for 1/8 of them
      int divisor = Platform.isAndroid ? 8 : 1;
      await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15), continuousUpdates: true, continuousDivisor: divisor);
    } catch (e) {
      SnackbarTools.show(ABC.b, prettyException("Start Scan Error:", e), success: false);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future onStopPressed() async {
    try {
      FlutterBluePlus.stopScan();
    } catch (e) {
      SnackbarTools.show(ABC.b, prettyException("Stop Scan Error:", e), success: false);
    }
  }

  void onConnectPressed(BluetoothDevice device) async {
    // device.connectAndUpdateStream().catchError((e) {
    await device.connect().catchError((e) {
      debugPrint(e);
      SnackbarTools.show(ABC.c, prettyException("Connect Error:", e), success: false);
    });

    await device.discoverServices();

    attachBLEdevice(device);

    // MaterialPageRoute route = MaterialPageRoute(
    //     builder: (context) => DeviceScreen(device: device), settings: RouteSettings(name: '/DeviceScreen'));
    // Navigator.push(context, route);
    // Navigator.of(context).pushNamed("/ble_device", device);
  }

  Future onRefresh() {
    if (_isScanning == false) {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    }
    if (mounted) {
      setState(() {});
    }
    return Future.delayed(const Duration(milliseconds: 500));
  }

  Widget buildScanButton(BuildContext context) {
    if (FlutterBluePlus.isScanningNow) {
      return FloatingActionButton(
        onPressed: onStopPressed,
        backgroundColor: Colors.red,
        child: const Icon(Icons.stop),
      );
    } else {
      return FloatingActionButton(onPressed: onScanPressed, child: const Text("SCAN"));
    }
  }

  List<Widget> _buildSystemDeviceTiles(BuildContext context) {
    return _systemDevices
        .map(
          (d) => SystemDeviceTile(
            device: d,
            // onOpen: () => Navigator.of(context).push(
            //   MaterialPageRoute(
            //     builder: (context) => DeviceScreen(device: d),
            //     settings: RouteSettings(name: '/DeviceScreen'),
            //   ),
            // ),
            onDisconnect: () {
              d.disconnect();
              onScanPressed();
            },
            onConnect: () => onConnectPressed(d),
          ),
        )
        .toList();
  }

  List<Widget> _buildScanResultTiles(BuildContext context) {
    return _scanResults
        .where((element) => element.device.advName.contains("ServoCarb"))
        .map(
          (r) => ScanResultTile(
            result: r,
            onTap: () => onConnectPressed(r.device),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      ..._buildSystemDeviceTiles(context),
      ..._buildScanResultTiles(context),
    ];

    return ScaffoldMessenger(
      // key: SnackBar.snackBarKeyB,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Find Devices'),
        ),
        body: items.isNotEmpty
            ? RefreshIndicator(
                onRefresh: onRefresh,
                child: ListView(
                  children: items,
                ),
              )
            : const Center(
                child: Text("No ServoCarb devices found."),
              ),
        // floatingActionButton: buildScanButton(context),
      ),
    );
  }
}
