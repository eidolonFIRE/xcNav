import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';

class WeatherViewer extends StatefulWidget {
  const WeatherViewer({super.key});

  @override
  State<WeatherViewer> createState() => _WeatherViewerState();
}

class _WeatherViewerState extends State<WeatherViewer> {
  double? selectedY;
  final WebViewController controller = WebViewController();

  @override
  void initState() {
    super.initState();
    final myTelemetry = Provider.of<MyTelemetry>(context, listen: false);

    PackageInfo.fromPlatform().then((version) {
      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              return NavigationDecision.prevent;
            },
          ),
        );
      // Some fixes to map to ppg.report
      String distCoarse = getUnitStr(UnitType.distCoarse);
      if (distCoarse == "mi") distCoarse = "miles";
      String speed = getUnitStr(UnitType.speed);
      if (speed == "kts") speed = "knots";
      final String uri =
          "https://ppg.report/${myTelemetry.geo?.lat},${myTelemetry.geo?.lng}#user-speed-unit=$speed&user-distance-unit=$distCoarse&user-height-unit=${getUnitStr(UnitType.distFine)}&user-altitude=${settingsMgr.primaryAltimeter.value.name.toUpperCase()}";
      debugPrint(uri);
      controller
          .loadRequest(Uri.parse(uri), headers: {"xcNav": "${version.version}  -  ( build ${version.buildNumber}"});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Stack(
      children: [
        WebViewWidget(
          controller: controller,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 20),
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              iconSize: 30,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ],
    ));
  }
}
