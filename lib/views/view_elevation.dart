import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barometer/flutter_barometer.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/dem_service.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/elevation_plot.dart';
import 'package:xcnav/widgets/map_marker.dart';

class ViewElevation extends StatefulWidget {
  const ViewElevation({Key? key}) : super(key: key);

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

  TextEditingController barometerTextController = TextEditingController();

  List<Duration?> lookBehindOptions = [
    null,
    const Duration(minutes: 60),
    const Duration(minutes: 30),
    const Duration(minutes: 10),
  ];

  Future<List<ElevSample?>> doSamples(Geo geo, Waypoint? waypoint) async {
    waypointETA = waypoint?.eta(geo, geo.spdSmooth);

    /// Use either the selected duration, or derive from ETA to waypoint (plus over-shoot a little)
    /// Max 200km
    double forecastDist = lookAhead is double
        ? lookAhead
        : ((waypointETA != null && waypointETA?.distance != null)
            ? min(200000, waypointETA!.distance * 1.2)
            : (Provider.of<Settings>(context, listen: false).displayUnitsDist == DisplayUnitsDist.metric
                ? 10000.0
                : 8046.72));
    final sampleInterval = max(100, forecastDist / 30).ceil();

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
    final activePlan = Provider.of<ActivePlan>(context, listen: false);

    // --- Build view options
    final isMetric = Provider.of<Settings>(context, listen: false).displayUnitsDist == DisplayUnitsDist.metric;
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
          // --- Flight Timer
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: myTelemetry.takeOff != null
                ? Builder(builder: (context) {
                    int remMin =
                        ((DateTime.now().millisecondsSinceEpoch - myTelemetry.takeOff!.millisecondsSinceEpoch) / 60000)
                            .ceil();
                    String value = (remMin >= 60) ? (remMin / 60).toStringAsFixed(1) : remMin.toString();
                    String unit = (remMin >= 60) ? " hr" : " min";
                    return Text.rich(TextSpan(children: [
                      const TextSpan(text: "Launched   ", style: TextStyle(color: Colors.grey)),
                      TextSpan(
                          text: DateFormat("h:mm a").format(myTelemetry.takeOff!),
                          style: Theme.of(context).textTheme.headline5),
                      const TextSpan(text: " ,    ", style: TextStyle(color: Colors.grey)),
                      TextSpan(text: value, style: Theme.of(context).textTheme.headline5),
                      TextSpan(text: unit, style: Theme.of(context).textTheme.headline6),
                      const TextSpan(text: "  ago.", style: TextStyle(color: Colors.grey)),
                    ]));
                  })
                : const Text(
                    "Flight timer stopped.",
                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                  ),
          ),

          // --- Barometer control
          ListTile(
            visualDensity: VisualDensity.compact,
            // leading: const Icon(Icons.thermostat),
            title: const Text("Ambient Pressure"),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    myTelemetry.fetchAmbPressure();
                  },
                  iconSize: 18,
                  icon: myTelemetry.baroFromWeatherkit
                      ? const Icon(Icons.public, color: Colors.lightGreen)
                      : const Icon(
                          Icons.public_off,
                          color: Colors.red,
                        )),
              Text(
                printDouble(value: myTelemetry.baroAmbient?.hectpascal ?? 1013.25, digits: 4, decimals: 2),
                style:
                    TextStyle(fontSize: 20, color: myTelemetry.baroFromWeatherkit ? Colors.lightGreen : Colors.white),
              ),
              const VerticalDivider(),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => {
                        setState(() {
                          myTelemetry.baroFromWeatherkit = false;
                          myTelemetry.baroAmbient =
                              BarometerValue((myTelemetry.baroAmbient?.hectpascal ?? 1013.25) + 0.25);
                        })
                      },
                  icon: const Icon(
                    Icons.add_circle,
                    size: 18,
                  )),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => {
                        setState(() {
                          myTelemetry.baroFromWeatherkit = false;
                          myTelemetry.baroAmbient =
                              BarometerValue((myTelemetry.baroAmbient?.hectpascal ?? 1013.25) - 0.25);
                        })
                      },
                  icon: const Icon(
                    Icons.remove_circle,
                    size: 18,
                  )),
            ]),
          ),

          if (!myTelemetry.inFlight && myTelemetry.baroAmbient != null && myTelemetry.ambientTemperature != null)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                "Density Altitude:",
                style: Theme.of(context).textTheme.headline6,
              ),
              const SizedBox(
                width: 20,
              ),
              Text.rich(richValue(
                  UnitType.distFine,
                  densityAlt(myTelemetry.baroAmbient!, myTelemetry.ambientTemperature!) +
                      (myTelemetry.geo.ground ?? myTelemetry.geo.alt),
                  digits: 6,
                  decimals: -2,
                  valueStyle: Theme.of(context).textTheme.headline4,
                  unitStyle: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))
            ]),

          Container(
            height: 40,
          ),

          // --- Elevation Plot
          if (myTelemetry.recordGeo.length > 1)
            Expanded(
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                // constraints: const BoxConstraints(maxHeight: 400),
                child: ClipRect(
                    child: FutureBuilder<List<ElevSample?>>(
                        future: doSamples(Provider.of<MyTelemetry>(context).geo, activePlan.getSelectedWp()),
                        builder: (context, groundSamples) {
                          final myTelemetry = Provider.of<MyTelemetry>(context, listen: false);
                          final oldestTimestamp = lookBehind != null
                              ? DateTime.fromMillisecondsSinceEpoch(myTelemetry.geo.time).subtract(lookBehind!)
                              : DateTime.fromMillisecondsSinceEpoch(myTelemetry.recordGeo.first.time);
                          return CustomPaint(
                            painter: ElevationPlotPainter(
                                myTelemetry.getHistory(oldestTimestamp, interval: const Duration(seconds: 30)),
                                groundSamples.data ?? [],
                                Provider.of<Settings>(context, listen: false).displayUnitsDist ==
                                        DisplayUnitsDist.metric
                                    ? 100
                                    : 152.4,
                                distScale,
                                waypoint: activePlan.getSelectedWp(),
                                waypointETA: waypointETA),
                          );
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
                              : const Text("All"))
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
                        switch (e.runtimeType) {
                          case double:
                            return e == lookAheadOptions.first
                                ? Text.rich(richValue(UnitType.distCoarse, e,
                                    unitStyle: const TextStyle(fontSize: 10, color: Colors.grey)))
                                : Text(printDouble(
                                    value: unitConverters[UnitType.distCoarse]!(e),
                                    digits: 3,
                                    decimals: 0,
                                    autoDecimalThresh: 1));

                          case WaypointID:
                            final selectedWp = activePlan.getSelectedWp()!;
                            return SizedBox(
                              width: 30,
                              height: 32,
                              child: selectedWp.isPath
                                  ? SvgPicture.asset("assets/images/path.svg", color: selectedWp.getColor())
                                  : MapMarker(selectedWp, 30),
                            );
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
  }
}
