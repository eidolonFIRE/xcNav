import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
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

  dynamic lookAhead = Duration(minutes: 10);
  Duration? lookBehind = Duration(minutes: 10);
  ETA? waypointETA;

  List<Duration?> lookBehindOptions = [
    null,
    const Duration(minutes: 60),
    const Duration(minutes: 30),
    const Duration(minutes: 10),
  ];

  Future<List<ElevSample?>> doSamples(Geo geo, Waypoint? waypoint) async {
    waypointETA = waypoint?.eta(geo, geo.spdSmooth);
    // TODO: this doesn't support first intersect from path correctly
    Duration forecastDuration = lookAhead.runtimeType == Duration
        ? lookAhead
        : ((waypointETA != null && waypointETA?.time != null)
            ? Duration(milliseconds: (waypointETA!.time!.inMilliseconds * 1.2).ceil())
            : const Duration(minutes: 10));
    final sampleInterval = Duration(milliseconds: (forecastDuration.inMilliseconds / 30).ceil());

    Completer<List<ElevSample?>> samplesCompleter = Completer();
    List<Completer<ElevSample?>> completers = [];

    /// Degrees
    double bearing = geo.hdg / pi * 180;
    if (waypoint != null) {
      bearing = latlngCalc.bearing(geo.latLng, waypoint.latlng.first);
    }

    // Build up a list of individual tasks that need to complete
    for (int t = 0; t <= forecastDuration.inMilliseconds; t += sampleInterval.inMilliseconds) {
      final Completer<ElevSample?> newCompleter = Completer();
      final sampleLatlng = waypoint?.isPath == true
          ? waypoint!
              .interpolate(
                  waypointETA!.distance * t / waypointETA!.time!.inMilliseconds, waypointETA!.pathIntercept!.index,
                  initialLatlng: geo.latLng)
              .latlng
          : latlngCalc.offset(geo.latLng, geo.spdSmooth * t / 1000, bearing);
      // debugPrint("${sampleLatlng}");
      sampleDem(sampleLatlng, false).then((value) {
        if (value != null) {
          newCompleter.complete(ElevSample(sampleLatlng, value, t));
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
    final activePlan = Provider.of<ActivePlan>(context, listen: false);

    // --- Build view options
    List<dynamic> lookAheadOptions = [
      const Duration(minutes: 10),
      const Duration(minutes: 30),
      const Duration(minutes: 60),
    ];
    if (activePlan.selectedWp != null) lookAheadOptions.add(activePlan.selectedWp);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // --- Flight Timer
        Consumer<MyTelemetry>(builder: (context, myTelemetry, _) {
          return ListTile(
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
                    "On the ground...",
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
          );
        }),

        Container(
          height: 40,
        ),

        // --- Elevation Plot
        Expanded(
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            // constraints: const BoxConstraints(maxHeight: 400),
            child: ClipRect(
                child: FutureBuilder<List<ElevSample?>>(
                    future: doSamples(Provider.of<MyTelemetry>(context).geo, activePlan.selectedWp),
                    builder: (context, groundSamples) {
                      final myTelemetry = Provider.of<MyTelemetry>(context, listen: false);
                      final oldestTimestamp = lookBehind != null
                          ? DateTime.fromMillisecondsSinceEpoch(myTelemetry.geo.time).subtract(lookBehind!)
                          : DateTime.fromMillisecondsSinceEpoch(myTelemetry.recordGeo.first.time);
                      return CustomPaint(
                        painter: ElevationPlotPainter(
                            myTelemetry.getHistory(oldestTimestamp, interval: Duration(seconds: 30)),
                            groundSamples.data ?? [],
                            Provider.of<Settings>(context, listen: false).displayUnitsDist == DisplayUnitsDist.metric
                                ? 100
                                : 152.4,
                            waypoint: activePlan.selectedWp,
                            waypointETA: waypointETA),
                      );
                    })),
          ),
        ),

        // --- View Controls
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ToggleButtons(
                  borderRadius: BorderRadius.circular(20),
                  constraints: BoxConstraints(minWidth: (MediaQuery.of(context).size.width - 20) / 9, minHeight: 40),
                  onPressed: (index) => setState(() {
                        lookBehind = lookBehindOptions[index];
                      }),
                  isSelected: lookBehindOptions.map((e) => e == lookBehind).toList(),
                  children: lookBehindOptions.map((e) => Text(e != null ? "${e.inMinutes}" : "All")).toList()),
              const Expanded(
                  child: Divider(
                thickness: 2,
              )),
              ToggleButtons(
                  borderRadius: BorderRadius.circular(20),
                  constraints: BoxConstraints(minWidth: (MediaQuery.of(context).size.width - 20) / 9, minHeight: 40),
                  onPressed: (index) => setState(() {
                        lookAhead = lookAheadOptions[index];
                      }),
                  isSelected: lookAheadOptions.map((e) => e == lookAhead).toList(),
                  children: lookAheadOptions.map((e) {
                    switch (e.runtimeType) {
                      case Duration:
                        return Text("${e.inMinutes}");

                      case Waypoint:
                        return SizedBox(
                          width: 30,
                          height: 30,
                          child: activePlan.selectedWp!.isPath
                              ? SvgPicture.asset("assets/images/path.svg", color: activePlan.selectedWp!.getColor())
                              : MapMarker(activePlan.selectedWp!, 30),
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
  }
}
