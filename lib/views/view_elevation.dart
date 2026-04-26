import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

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

class ViewElevationState extends State<ViewElevation> {
  // ignore: annotate_overrides
  bool get wantKeepAlive => true;

  List<ElevSample> elevSamples = [];

  dynamic lookAhead;
  Duration? lookBehind = const Duration(minutes: 10);
  ETA? waypointETA;

  double distScale = 100;

  List<ElevSample?>? prevSamples;

  final barometerTextController = TextEditingController();

  List<Duration?> lookBehindOptions = [
    null,
    const Duration(minutes: 60),
    const Duration(minutes: 30),
    const Duration(minutes: 10),
  ];

  List<ElevSample> doSamples(Geo geo, Waypoint? waypoint, double speed) {
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
    final List<ElevSample> values = [];
    for (double dist = 0; dist < forecastDist; dist += sampleInterval) {
      final sampleLatlng = (waypoint != null && waypointETA != null)
          ? waypoint.interpolate(dist, waypointETA!.pathIntercept?.index ?? 0, initialLatlng: geo.latlng).latlng
          : latlngCalc.offset(geo.latlng, dist, geo.hdg / pi * 180);
      final elev = sampleDem(sampleLatlng, false);
      if (elev != null) {
        values.add(ElevSample(sampleLatlng, dist * distScale, elev));
      }
    }
    return values;
  }

  @override
  Widget build(BuildContext context) {
    // super.build(context);
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
      return ListenableBuilder(
          listenable: myTelemetry,
          builder: (context, _) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // --- Elevation Plot
                if (myTelemetry.recordGeo.length > 1)
                  Expanded(
                      child: SizedBox(
                          width: MediaQuery.of(context).size.width,
                          // constraints: const BoxConstraints(maxHeight: 400),
                          child: ClipRect(
                              child: CustomPaint(
                            painter: ElevationPlotPainter(
                                myTelemetry.getHistory(
                                    lookBehind != null
                                        ? DateTime.fromMillisecondsSinceEpoch(myTelemetry.recordGeo.last.time)
                                            .subtract(lookBehind!)
                                        : DateTime.fromMillisecondsSinceEpoch(myTelemetry.recordGeo.first.time),
                                    interval: const Duration(seconds: 30)),
                                doSamples(myTelemetry.recordGeo.last, activePlan.getSelectedWp(),
                                    myTelemetry.speedSmooth.value),
                                distScale,
                                waypoint: activePlan.getSelectedWp(),
                                waypointETA: waypointETA,
                                liveSpeed: myTelemetry.speedSmooth.value,
                                liveVario: myTelemetry.varioSmooth.value),
                          )))),

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
