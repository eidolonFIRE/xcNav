import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:xcnav/dem_service.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/elevation_plot.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

class ViewElevation extends StatefulWidget {
  const ViewElevation({super.key});

  @override
  State<ViewElevation> createState() => ViewElevationState();
}

class ViewElevationState extends State<ViewElevation> with AutomaticKeepAliveClientMixin<ViewElevation> {
  // ignore: annotate_overrides
  bool get wantKeepAlive => true;

  List<ElevSample> elevSamples = [];

  dynamic lookAhead;
  Duration? lookBehind = const Duration(minutes: 10);
  ETA? waypointETA;

  double distScale = 100;

  List<ElevSample?>? prevSamples;

  TextEditingController barometerTextController = TextEditingController();

  List<Duration?> lookBehindOptions = [
    null,
    const Duration(minutes: 60),
    const Duration(minutes: 30),
    const Duration(minutes: 10),
  ];

  Future<List<ElevSample?>> doSamples(Geo geo, Waypoint? waypoint, double speed) async {
    waypointETA = waypoint?.eta(geo, speed);

    /// Use either the selected duration, or derive from ETA to waypoint (plus over-shoot a little)
    /// Max 200km
    double forecastDist = lookAhead is double
        ? lookAhead
        : ((waypointETA != null && waypointETA?.distance != null)
            ? min(200000, waypointETA!.distance * 1.2)
            : (settingsMgr.displayUnitDist.value == DisplayUnitsDist.metric ? 10000.0 : 8046.72));
    // `max` check here will only save computer for nearby points by setting min resolution to 20.
    final sampleInterval = max(20, forecastDist / 100).ceil();
    // debugPrint("DEM sample interval: $sampleInterval");

    Completer<List<ElevSample?>> samplesCompleter = Completer();
    List<Completer<ElevSample?>> completers = [];

    // Build up a list of individual tasks that need to complete
    // debugPrint("ForecastDist: ${forecastDist}, Interval: ${sampleInterval}");
    for (double dist = 0; dist < forecastDist; dist += sampleInterval) {
      final Completer<ElevSample?> newCompleter = Completer();
      final sampleLatlng = (waypoint != null && waypointETA != null)
          ? waypoint.interpolate(dist, waypointETA!.pathIntercept?.index ?? 0, initialLatlng: geo.latlng).latlng
          : latlngCalc.offset(geo.latlng, dist, geo.hdg / pi * 180);
      // debugPrint("${sampleLatlng}");
      sampleDem(sampleLatlng, false).then((elevation) {
        if (elevation != null) {
          newCompleter.complete(ElevSample(sampleLatlng, dist * distScale, elevation));
        } else {
          newCompleter.complete(null);
        }
      });
      completers.add(newCompleter);
    }

    // Wait for all the samples to complete
    Future.wait(completers.map((e) => e.future).toList()).then((value) => samplesCompleter.complete(value));
    return samplesCompleter.future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    debugPrint("Build /view_elevation");

    return Consumer<ActivePlan>(builder: (context, activePlan, _) {
      // --- Build view options
      final isMetric = settingsMgr.displayUnitDist.value == DisplayUnitsDist.metric;
      List<dynamic> lookAheadOptions = [
        isMetric ? 10000 : 8046.72, // 5mi
        isMetric ? 20000 : 16093.44, // 10mi
        isMetric ? 100000 : 80467.2, // 50mi
      ];
      lookAhead = lookAhead ?? lookAheadOptions.first;
      if (activePlan.selectedWp != null) lookAheadOptions.add(activePlan.selectedWp);
      return Consumer<MyTelemetry>(builder: (context, myTelemetry, _) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (Platform.isIOS)
              GestureDetector(
                onTap: () => launchUrl(Uri.parse("https://weatherkit.apple.com/legal-attribution.html")),
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Image.asset(
                    "assets/external/apple_weather.png",
                    height: 20,
                  ),
                ),
              ),
            // --- Barometer control
            ListTile(
              minVerticalPadding: 20,
              visualDensity: VisualDensity.compact,
              // leading: const Icon(Icons.thermostat),
              title: Text("Ambient Pressure".tr()),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      if (myTelemetry.geo != null) myTelemetry.fetchAmbPressure(myTelemetry.geo!.latlng);
                    },
                    iconSize: 18,
                    icon: myTelemetry.baroFromWeatherkit
                        ? const Icon(Icons.public, color: Colors.lightGreen)
                        : const Icon(
                            Icons.public_off,
                            color: Colors.red,
                          )),
                Text(
                  printDouble(value: myTelemetry.baroAmbient?.pressure ?? 1013.25, digits: 4, decimals: 2),
                  style:
                      TextStyle(fontSize: 20, color: myTelemetry.baroFromWeatherkit ? Colors.lightGreen : Colors.white),
                ),
                VerticalDivider(
                  color: Colors.grey.shade900,
                ),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => {
                          setState(() {
                            myTelemetry.baroFromWeatherkit = false;
                            myTelemetry.baroAmbient =
                                BarometerEvent((myTelemetry.baroAmbient?.pressure ?? 1013.25) + 0.25, clock.now());
                          })
                        },
                    icon: const Icon(
                      Icons.add_circle,
                      size: 20,
                    )),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => {
                          setState(() {
                            myTelemetry.baroFromWeatherkit = false;
                            myTelemetry.baroAmbient =
                                BarometerEvent((myTelemetry.baroAmbient?.pressure ?? 1013.25) - 0.25, clock.now());
                          })
                        },
                    icon: const Icon(
                      Icons.remove_circle,
                      size: 20,
                    )),
              ]),
            ),

            Divider(
              height: 0,
              color: Colors.grey.shade900,
            ),

            // --- Density Altitude
            if (!myTelemetry.inFlight &&
                myTelemetry.baroAmbient != null &&
                myTelemetry.ambientTemperature != null &&
                myTelemetry.geo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                    "Density Altitude".tr(),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(
                    width: 20,
                  ),
                  Text.rich(richValue(
                      UnitType.distFine,
                      densityAlt(myTelemetry.baroAmbient!, myTelemetry.ambientTemperature!) +
                          (myTelemetry.geo!.ground ?? myTelemetry.geo!.alt),
                      digits: 6,
                      decimals: -2,
                      valueStyle: Theme.of(context).textTheme.headlineMedium,
                      unitStyle: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))
                ]),
              ),

            // --- GPS Altitude
            if (myTelemetry.geo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                    "GPS Altitude".tr(),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(
                    width: 20,
                  ),
                  Text.rich(richValue(UnitType.distFine, myTelemetry.geo!.altGps,
                      digits: 6,
                      decimals: -2,
                      valueStyle: Theme.of(context).textTheme.headlineMedium,
                      unitStyle: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))
                ]),
              ),

            // --- Elevation Plot
            if (myTelemetry.recordGeo.length > 1)
              Expanded(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  // constraints: const BoxConstraints(maxHeight: 400),
                  child: ClipRect(
                      child: FutureBuilder<List<ElevSample?>>(
                          future: doSamples(
                              myTelemetry.recordGeo.last, activePlan.getSelectedWp(), myTelemetry.speedSmooth.value),
                          initialData: prevSamples ?? [],
                          builder: (context, groundSamples) {
                            prevSamples = groundSamples.data;
                            final myTelemetry = Provider.of<MyTelemetry>(context, listen: false);
                            final oldestTimestamp = lookBehind != null
                                ? DateTime.fromMillisecondsSinceEpoch(myTelemetry.recordGeo.last.time)
                                    .subtract(lookBehind!)
                                : DateTime.fromMillisecondsSinceEpoch(myTelemetry.recordGeo.first.time);
                            final history =
                                myTelemetry.getHistory(oldestTimestamp, interval: const Duration(seconds: 30));
                            if (history.length < 2) {
                              return const Center(
                                  child: SizedBox(width: 60, height: 60, child: CircularProgressIndicator()));
                            } else {
                              return CustomPaint(
                                painter: ElevationPlotPainter(history, groundSamples.data ?? [], distScale,
                                    waypoint: activePlan.getSelectedWp(),
                                    waypointETA: waypointETA,
                                    liveSpeed: myTelemetry.speedSmooth.value,
                                    liveVario: myTelemetry.varioSmooth.value),
                              );
                            }
                          })),
                ),
              ),

            // --- View Controls
            if (myTelemetry.recordGeo.length > 1)
              Padding(
                padding: const EdgeInsets.all(4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ToggleButtons(
                        borderRadius: BorderRadius.circular(20),
                        constraints:
                            BoxConstraints(minWidth: (MediaQuery.of(context).size.width - 20) / 9, minHeight: 40),
                        onPressed: (index) => setState(() {
                              lookBehind = lookBehindOptions[index];
                            }),
                        isSelected: lookBehindOptions.map((e) => e == lookBehind).toList(),
                        children: lookBehindOptions
                            .map((e) => e != null
                                ? (e != lookBehindOptions.last
                                    ? Text("${e.inMinutes}")
                                    : Text.rich(richHrMin(
                                        duration: e, unitStyle: const TextStyle(fontSize: 10, color: Colors.grey))))
                                : Text("btn.All".tr()))
                            .toList()),
                    const Expanded(
                        child: Divider(
                      thickness: 2,
                    )),
                    ToggleButtons(
                        borderRadius: BorderRadius.circular(20),
                        constraints:
                            BoxConstraints(minWidth: (MediaQuery.of(context).size.width - 20) / 9, minHeight: 40),
                        onPressed: (index) => setState(() {
                              lookAhead = lookAheadOptions[index];
                            }),
                        isSelected: lookAheadOptions.map((e) => e == lookAhead).toList(),
                        children: lookAheadOptions.map((e) {
                          switch (e.runtimeType.toString()) {
                            case "double":
                              return e == lookAheadOptions.first
                                  ? Text.rich(richValue(UnitType.distCoarse, e,
                                      unitStyle: const TextStyle(fontSize: 10, color: Colors.grey)))
                                  : Text(printValue(UnitType.distCoarse, e,
                                          digits: 3, decimals: 0, autoDecimalThresh: 1) ??
                                      "");

                            case "String":
                              final selectedWp = activePlan.getSelectedWp();
                              if (selectedWp == null) {
                                return Container();
                              } else {
                                return SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: selectedWp.isPath
                                      ? SvgPicture.asset(
                                          "assets/images/path.svg",
                                          colorFilter: ColorFilter.mode(selectedWp.getColor(), BlendMode.srcIn),
                                        )
                                      : WaypointMarker(selectedWp, 30),
                                );
                              }
                            default:
                              return Container();
                          }
                        }).toList()),
                  ],
                ),
              ),

            Container(
              height: 20,
            )
          ],
        );
      });
    });
  }
}
