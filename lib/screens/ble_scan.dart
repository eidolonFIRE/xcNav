import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_svg/svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:xcnav/services/ble_service.dart' as ble_service;

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
            title: const Text('Bluetooth Devices'),
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

                        return ListTile(
                          title: Text(device.advName),
                          trailing: device.isConnected
                              ? ElevatedButton.icon(
                                  onPressed: () {
                                    device.disconnect().then((_) {
                                      setState(() {});
                                    });
                                  },
                                  label: Text("btn.Disconnect".tr()),
                                  icon: Icon(Icons.close),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () {
                                    ble_service.connect(device).then((_) {
                                      setState(() {});
                                    });
                                  },
                                  label: Text("btn.Connect".tr()),
                                  icon: Icon(Icons.add),
                                ),
                        );
                      });
                }),
          )),
    );
  }
}
