import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/datadog.dart';

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

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {},
          onHttpError: (HttpResponseError e) {
            error("HttpError (${e.response?.statusCode}) ${e.response?.uri.toString()}");
          },
          onWebResourceError: (WebResourceError e) {
            error("WebResource (${e.errorCode}) ${e.description}");
          },
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
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
    controller.loadRequest(Uri.parse(uri), headers: {"xcNav": "${version.version}  -  ( build ${version.buildNumber}"});
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
