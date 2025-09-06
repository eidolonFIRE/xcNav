import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_svg/svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:xcnav/services/ble_service.dart' as ble_service;
import 'package:xcnav/settings_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  void initState() {
    super.initState();
    ble_service.scan();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
        child: Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth Devices'.tr()),
        actions: [
          StreamBuilder<bool>(
              stream: FlutterBluePlus.isScanning,
              builder: (context, isScanning) {
                return IconButton(
                  icon: (isScanning.data ?? false)
                      ? SizedBox(width: 26, height: 26, child: CircularProgressIndicator.adaptive())
                      : Icon(Icons.refresh),
                  onPressed: () {
                    if (!(isScanning.data ?? false)) {
                      ble_service.scan();
                    }
                  },
                );
              }),
        ],
      ),
      body: DefaultTextStyle(
          style: const TextStyle(fontSize: 20),
          child: StreamBuilder(
              stream: FlutterBluePlus.scanResults,
              builder: (context, results) {
                if (results.hasData && results.data!.isEmpty) {
                  return Center(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text("dont_see_device".tr()),
                            Text("only_some_device_supported".tr(), textAlign: TextAlign.center),
                            SizedBox(
                              width: MediaQuery.of(context).size.width / 5,
                              height: MediaQuery.of(context).size.width / 5,
                              child: ElevatedButton(
                                  style: ButtonStyle(
                                    side: WidgetStateProperty.resolveWith<BorderSide>(
                                        (states) => const BorderSide(color: Colors.white)),
                                    backgroundColor: WidgetStateProperty.resolveWith<Color>((states) => Colors.white),
                                    // minimumSize: WidgetStateProperty.resolveWith<Size>((states) => const Size(30, 40)),
                                    padding: WidgetStateProperty.resolveWith<EdgeInsetsGeometry>(
                                        (states) => const EdgeInsets.all(20)),
                                    shape: WidgetStateProperty.resolveWith<OutlinedBorder>((_) {
                                      return RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));
                                    }),
                                    textStyle: WidgetStateProperty.resolveWith<TextStyle>(
                                        (states) => const TextStyle(color: Colors.white, fontSize: 22)),
                                  ),
                                  onPressed: () => {launchUrl(Uri.parse("https://discord.gg/Fwv8Sz4HJN"))},
                                  child: SvgPicture.asset(
                                    "assets/external/icon_clyde_white_RGB.svg",
                                  )),
                            ),
                          ].map((e) => Padding(padding: EdgeInsets.all(8.0), child: e)).toList()));
                }
                return ListView.builder(
                    itemCount: results.data?.length ?? 0,
                    itemBuilder: (context, index) {
                      final device = results.data![index].device;

                      return Card(
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                          margin: EdgeInsets.all(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        WidgetSpan(
                                            alignment: PlaceholderAlignment.middle,
                                            child: Icon(
                                              Icons.bluetooth,
                                              size: 30,
                                            )),
                                        TextSpan(text: device.advName)
                                      ],
                                    ),
                                    style: TextStyle(fontSize: 30),
                                  ),
                                  if (device.isConnected)
                                    IconButton(
                                        onPressed: () {
                                          if (context.mounted) {
                                            final handler = ble_service.getHandler(deviceId: device.remoteId);
                                            if (handler != null) {
                                              showDialog(
                                                  context: context, builder: (context) => handler.configDialog());
                                            }
                                          }
                                        },
                                        icon: Icon(Icons.settings)),
                                ],
                              ),
                              Container(
                                height: 10,
                              ),
                              // --- Bottom row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // --- Auto Connect Label+Button
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text("Auto Connect".tr()),
                                    Switch.adaptive(
                                        value: settingsMgr.bleAutoDevices.value.contains(device.remoteId.str),
                                        onChanged: (value) {
                                          setState(() {
                                            if (value && device.isDisconnected) {
                                              ble_service.connect(device);
                                              // Add to list
                                              if (!settingsMgr.bleAutoDevices.value.contains(device.remoteId.str)) {
                                                settingsMgr.bleAutoDevices.value =
                                                    settingsMgr.bleAutoDevices.value + [device.remoteId.str];
                                              }
                                            }
                                            if (!value) {
                                              // Remove from list
                                              final wasRemoved =
                                                  settingsMgr.bleAutoDevices.value.remove(device.remoteId.str);
                                              if (wasRemoved) {
                                                // Trigger save by setting value
                                                settingsMgr.bleAutoDevices.value = settingsMgr.bleAutoDevices.value;
                                              }
                                            }
                                          });
                                        }),
                                  ]),

                                  StreamBuilder(
                                    stream: device.connectionState,
                                    builder: (context, connected) =>
                                        connected.data == BluetoothConnectionState.connected
                                            ? ElevatedButton.icon(
                                                onPressed: () {
                                                  ble_service.disconnect(device);
                                                },
                                                label: Text("btn.Disconnect".tr()),
                                                icon: Icon(Icons.close),
                                              )
                                            : ElevatedButton.icon(
                                                onPressed: () {
                                                  ble_service.connect(device);
                                                },
                                                label: Text("btn.Connect".tr()),
                                                icon: Icon(Icons.add),
                                              ),
                                  )
                                ],
                              ),
                            ]),
                          ));
                    });
              })),
    ));
  }
}
