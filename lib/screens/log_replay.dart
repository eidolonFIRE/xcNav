import 'dart:math';
import 'dart:ui';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart' as intl;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:collection/collection.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import 'package:xcnav/dialogs/confirm_log_trim.dart';
import 'package:xcnav/dialogs/edit_gear.dart';
import 'package:xcnav/dialogs/edit_fuel_report.dart';
import 'package:xcnav/douglas_peucker.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';
import 'package:xcnav/widgets/log_summary.dart';
import 'package:xcnav/widgets/map_selector.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

class LogReplay extends StatefulWidget {
  const LogReplay({super.key});

  @override
  State<LogReplay> createState() => _LogReplayState();
}

class _LogReplayState extends State<LogReplay> with SingleTickerProviderStateMixin {
  final mapKey = GlobalKey(debugLabel: "replayMap");
  final mapController = MapController();
  bool mapReady = false;
  bool northLock = true;
  MapTileSrc mapTileSrc = MapTileSrc.topo;
  bool hideWaypoints = false;
  double mapOpacity = 1.0;
  ValueNotifier<bool> isMapDialOpen = ValueNotifier(false);

  String? logKey;
  late FlightLog log;

  ValueNotifier<int> sampleIndex = ValueNotifier(0);
  bool hasScrubbed = false;

  final lowerStyle = const TextStyle(color: Colors.black, fontSize: 20);
  final TextStyle unitStyle = const TextStyle(fontSize: 12, color: Colors.black87, fontStyle: FontStyle.italic);

  late final TabController tabController;

  final PageController gForcePageController = PageController();

  double mainDividerPosition = -1;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  void infoSetTrimTime(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => const AlertDialog(
              content: Text("Use the slider to select the trim position."),
            ));
  }

  void gotoGForce(int index) {
    if (tabController.index != 3) {
      tabController.animateTo(3, duration: const Duration(milliseconds: 200));
      Future.delayed(const Duration(milliseconds: 220)).then((_) => gForcePageController.jumpToPage(index));
    } else {
      gForcePageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.decelerate);
    }
  }

  void gotoGeo(int index) {
    sampleIndex.value = index;
    mapController.move(log.samples[index].latlng, mapController.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, Object>;
    logKey ??= args["logKey"] as String;

    log = logStore.logs[logKey]!;

    if (mainDividerPosition < 0) {
      mainDividerPosition = MediaQuery.of(context).size.height * 0.5;
    }

    final logGForceIndeces =
        log.gForceEvents.map((e) => log.timeToSampleIndex(DateTime.fromMillisecondsSinceEpoch(e.center.time))).toList();
    return PopScope(
      onPopInvokedWithResult: (_, __) {
        if (log.goodFile && log.unsaved) {
          log.save();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text("Replay:  ${log.title}"),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case "edit_gear":
                    editGear(context, gear: log.gear).then((newGear) {
                      if (newGear != null) {
                        logStore.logs[logKey!]!.gear = newGear;
                      }
                    });

                    break;
                  case "trim_start":
                    if (sampleIndex.value == 0 || sampleIndex.value >= log.samples.length - 1) {
                      // Alert if bad time selected
                      infoSetTrimTime(context);
                    } else {
                      //
                      final trimStartTime = DateTime.fromMillisecondsSinceEpoch(log.samples[sampleIndex.value].time);
                      final trimLength =
                          trimStartTime.difference(DateTime.fromMillisecondsSinceEpoch(log.samples.first.time));
                      confirmLogTrim(context,
                              cutLabel: "Start",
                              newTime: trimStartTime,
                              trimLength: trimLength,
                              sampleCount: sampleIndex.value)
                          .then((confirmed) {
                        setState(() {
                          if (confirmed ?? false) {
                            final newLog = log.trimLog(sampleIndex.value, log.samples.length - 1);
                            logStore.updateLog(logKey!, newLog);
                            gotoGeo(0);
                          }
                        });
                      });
                    }
                    break;
                  case "trim_end":
                    if (sampleIndex.value == 0 || sampleIndex.value >= log.samples.length - 1) {
                      // Alert if bad time selected
                      infoSetTrimTime(context);
                    } else {
                      //
                      final trimEndTime = DateTime.fromMillisecondsSinceEpoch(log.samples[sampleIndex.value].time);
                      final trimLength =
                          DateTime.fromMillisecondsSinceEpoch(log.samples.last.time).difference(trimEndTime);
                      confirmLogTrim(context,
                              cutLabel: "End",
                              newTime: trimEndTime,
                              trimLength: trimLength,
                              sampleCount: (log.samples.length - 1) - sampleIndex.value)
                          .then((confirmed) {
                        setState(() {
                          if (confirmed ?? false) {
                            final newLog = log.trimLog(0, sampleIndex.value);
                            logStore.updateLog(logKey!, newLog);
                            gotoGeo(log.samples.length - 1);
                          }
                        });
                      });
                    }
                    break;
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem(
                  value: "edit_gear",
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text("Edit Gear"),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                    value: "trim_start",
                    child: ListTile(
                      leading: SvgPicture.asset(
                        "assets/images/trim_start.svg",
                        height: 32,
                      ),
                      title: const Text(
                        "Trim Start",
                        style: TextStyle(color: Colors.amber),
                      ),
                    )),
                PopupMenuItem(
                    value: "trim_end",
                    child: ListTile(
                      leading: SvgPicture.asset(
                        "assets/images/trim_end.svg",
                        height: 32,
                      ),
                      title: const Text(
                        "Trim End",
                        style: TextStyle(color: Colors.amber),
                      ),
                    ))
              ],
            )
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            // --- Map
            if (mainDividerPosition > 1)
              SizedBox(
                height: mainDividerPosition,
                child: (mainDividerPosition < 80)
                    ? Container()
                    : Stack(children: [
                        FlutterMap(
                            key: mapKey,
                            mapController: mapController,
                            options: MapOptions(
                              initialCameraFit: CameraFit.bounds(bounds: log.getBounds()),
                              onMapReady: () {
                                setState(() {
                                  mapReady = true;
                                });
                              },
                              interactionOptions: InteractionOptions(
                                  flags: InteractiveFlag.all &
                                      (northLock ? ~InteractiveFlag.rotate : InteractiveFlag.all)),
                              onPositionChanged: (mapPosition, hasGesture) {
                                if (hasGesture) {
                                  isMapDialOpen.value = false;
                                }
                              },
                            ),
                            children: [
                              Opacity(opacity: mapOpacity, child: getMapTileLayer(mapTileSrc)),

                              // Waypoints: paths
                              if (!hideWaypoints)
                                PolylineLayer(
                                  polylines: log.waypoints
                                      .where((value) => value.latlng.length > 1)
                                      .map((e) => Polyline(points: e.latlng, strokeWidth: 6.0, color: e.getColor()))
                                      .toList(),
                                ),

                              // Waypoint markers
                              if (!hideWaypoints)
                                MarkerLayer(
                                    markers: log.waypoints
                                        .where((e) => e.latlng.length == 1)
                                        .map((e) => Marker(
                                            point: e.latlng[0],
                                            height: 60 * 0.8,
                                            width: 40 * 0.8,
                                            rotate: true,
                                            alignment: Alignment.topCenter,
                                            child: WaypointMarker(e, 60 * 0.8)))
                                        .toList()),

                              // --- Log Line
                              PolylineLayer(polylines: [
                                Polyline(
                                    points: log.samples.map((e) => e.latlng).toList(),
                                    strokeWidth: 4,
                                    color: Colors.red,
                                    pattern: const StrokePattern.dotted())
                              ]),

                              // --- G-Force Events
                              MarkerLayer(
                                  markers: log.gForceEvents
                                      .mapIndexed((i, e) => Marker(
                                          point: e.center.latlng,
                                          child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                gotoGForce(i);
                                              },
                                              child: Card(
                                                color: Colors.black.withAlpha(100),
                                                child: const Icon(
                                                  Icons.g_mobiledata,
                                                  color: Colors.lightGreen,
                                                  size: 20,
                                                ),
                                              ))))
                                      .toList()),

                              // --- Fuel reports
                              MarkerLayer(
                                markers: log.fuelReports
                                    .mapIndexed((index, e) => Marker(
                                        alignment: Alignment.topRight,
                                        height: 40,
                                        width: 60,
                                        point: log.samples[log.timeToSampleIndex(e.time)].latlng,
                                        child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                gotoGeo(log.timeToSampleIndex(e.time));
                                              });
                                            },
                                            onLongPress: () {
                                              editFuelReport(context, e.time, e.amount).then((newReport) {
                                                setState(() {
                                                  if (newReport != null) {
                                                    if (newReport.amount == 0 &&
                                                        newReport.time.millisecondsSinceEpoch == 0) {
                                                      // Report was deleted
                                                      log.removeFuelReport(index);
                                                    } else {
                                                      // Edit fuel report amount
                                                      log.updateFuelReport(index, newReport.amount);
                                                    }
                                                  }
                                                });
                                              });
                                            },

                                            // Fuel Report Marker
                                            child: LabelFlag(
                                                direction: TextDirection.ltr,
                                                text: Text.rich(
                                                  richValue(UnitType.fuel, e.amount, decimals: 1),
                                                  style: const TextStyle(color: Colors.white),
                                                ),
                                                color: Colors.blue))))
                                    .toList(),
                              ),

                              // "ME" Location Marker
                              ValueListenableBuilder<int>(
                                  valueListenable: sampleIndex,
                                  builder: (context, value, _) {
                                    return MarkerLayer(
                                      markers: [
                                        Marker(
                                          width: 30.0,
                                          height: 30.0,
                                          point: log.samples[value].latlng,
                                          child: Container(
                                            transformAlignment: const Alignment(0, 0),
                                            transform: Matrix4.rotationZ(log.samples[value].hdg),
                                            child: Image.asset("assets/images/red_arrow.png"),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                            ]),

                        // --- Map Tile Selector
                        Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: SizedBox(
                                  height: 40,
                                  child: MapSelector(
                                    isMapDialOpen: isMapDialOpen,
                                    curLayer: mapTileSrc,
                                    curOpacity: mapOpacity,
                                    hideWaypoints: hideWaypoints,
                                    onChangedWaypoints: (hidden) {
                                      setState(() {
                                        hideWaypoints = hidden;
                                      });
                                    },
                                    onChanged: ((layerName, opacity) {
                                      setState(() {
                                        mapTileSrc = layerName;
                                        mapOpacity = opacity;
                                      });
                                    }),
                                  )),
                            )),

                        // --- Time Scrubber
                        ValueListenableBuilder<int>(
                            valueListenable: sampleIndex,
                            builder: (context, index, _) {
                              return Positioned(
                                  bottom: 10,
                                  left: 10,
                                  right: 10,
                                  child: Theme(
                                    data: ThemeData(
                                        sliderTheme: const SliderThemeData(
                                      showValueIndicator: ShowValueIndicator.never,
                                      thumbShape: _ThumbShape(),
                                      activeTrackColor: Color.fromARGB(170, 0, 0, 0),
                                      inactiveTrackColor: Colors.black45,
                                      valueIndicatorColor: Colors.black45,
                                      thumbColor: Colors.black,
                                      trackHeight: 8,
                                    )),
                                    child: Slider(
                                        label: intl.DateFormat("h:mm a")
                                            .format(DateTime.fromMillisecondsSinceEpoch(log.samples[index].time)),
                                        value: (log.samples[index].time - log.startTime!.millisecondsSinceEpoch) /
                                            log.durationTime.inMilliseconds,
                                        onChanged: (value) {
                                          sampleIndex.value = max(
                                              0,
                                              min(
                                                  log.samples.length - 1,
                                                  log.timeToSampleIndex(log.startTime!.add(Duration(
                                                      milliseconds:
                                                          (value * log.durationTime.inMilliseconds).round())))));
                                        }),
                                  ));
                            }),

                        // --- Instruments
                        ValueListenableBuilder<int>(
                            valueListenable: sampleIndex,
                            builder: (context, value, _) {
                              return Positioned(
                                  left: 4,
                                  top: 4,
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                                        child: Container(
                                          color: Colors.white38,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  // --- Speedometer
                                                  Text.rich(richValue(UnitType.speed, log.samples[value].spd,
                                                      digits: 4,
                                                      autoDecimalThresh: -1,
                                                      valueStyle: lowerStyle.merge(const TextStyle(fontSize: 30)),
                                                      unitStyle: unitStyle)),

                                                  const SizedBox(
                                                      width: 40,
                                                      child: Divider(
                                                        color: Colors.grey,
                                                      )),

                                                  // --- Altimeter stack
                                                  Altimeter(
                                                    log.samples[value].alt,
                                                    valueStyle: lowerStyle,
                                                    unitStyle: unitStyle,
                                                    unitTag: "MSL",
                                                    isPrimary: false,
                                                  ),
                                                  if (log.samples[value].ground != null)
                                                    Altimeter(
                                                      log.samples[value].ground != null
                                                          ? log.samples[value].alt - log.samples[value].ground!
                                                          : null,
                                                      valueStyle: lowerStyle,
                                                      unitStyle: unitStyle,
                                                      unitTag: "AGL",
                                                      isPrimary: false,
                                                    ),
                                                ]),
                                          ),
                                        ),
                                      )));
                            }),
                      ]),
              ),

            SizedBox(
              height: 30,
              child: Center(
                  child: Listener(
                // onPointerDown: (event) {
                //   dividerDown = event;
                // },
                onPointerMove: (event) {
                  // if (dividerDown != null) {
                  setState(() {
                    mainDividerPosition =
                        min(MediaQuery.of(context).size.height - 350, max(0, mainDividerPosition + event.delta.dy));
                  });
                  // }
                },
                child: const Icon(Icons.drag_handle),
              )),
            ),

            /// ====================================
            ///
            ///     Lower Half
            ///
            /// ------------------------------------
            Expanded(
              child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  controller: tabController,
                  clipBehavior: Clip.none,
                  children: [
                    // --- Summary
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                      child: LogSummary(log: log),
                    ),

                    // --- Elevation Plot
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ValueListenableBuilder(
                            valueListenable: sampleIndex,
                            builder: (context, logIndex, _) {
                              return LineChart(
                                LineChartData(
                                    minY: unitConverters[UnitType.distFine]!(min(log.samples.map((e) => e.alt).min - 10,
                                        log.samples.map((e) => e.ground).nonNulls.min - 10)),
                                    extraLinesData: ExtraLinesData(verticalLines: [
                                      VerticalLine(
                                          x: log.samples[logIndex].time.toDouble(), color: Colors.white, strokeWidth: 1)
                                    ]),
                                    lineTouchData: LineTouchData(
                                      handleBuiltInTouches: false,
                                      getTouchedSpotIndicator: (barData, spotIndexes) {
                                        return spotIndexes
                                            .map((e) => TouchedSpotIndicatorData(const FlLine(strokeWidth: 0),
                                                    FlDotData(getDotPainter: (
                                                  FlSpot spot,
                                                  double xPercentage,
                                                  LineChartBarData bar,
                                                  int index, {
                                                  double? size,
                                                }) {
                                                  return FlDotCirclePainter(
                                                    radius: size ?? 5,
                                                    color: Colors.lightGreen,
                                                    strokeColor: Colors.grey,
                                                  );
                                                })))
                                            .toList();
                                      },
                                      touchCallback: (p0, p1) {
                                        if (p0 is FlTapUpEvent) {
                                          final index = p1?.lineBarSpots?.first.spotIndex;
                                          if (index != null) {
                                            List<int> dist = [];
                                            for (final each in logGForceIndeces) {
                                              dist.add((index - each).abs());
                                            }
                                            final closest = dist.min;
                                            final closestIndex = dist.indexOf(closest);
                                            if (closest < log.samples.length / 10) {
                                              // Go to g-force
                                              gotoGForce(closestIndex);
                                            }
                                          }
                                        }
                                      },
                                    ),
                                    lineBarsData: [
                                          LineChartBarData(
                                              color: Colors.orange.shade600,
                                              barWidth: 1,
                                              dotData: const FlDotData(show: false),
                                              spots: log.samples
                                                  .where((e) => e.ground != null)
                                                  .map((e) => FlSpot(
                                                      e.time.toDouble(), unitConverters[UnitType.distFine]!(e.ground!)))
                                                  .toList(),
                                              belowBarData: BarAreaData(
                                                show: true,
                                                color: Colors.orange.shade600,
                                              )),
                                          LineChartBarData(
                                              showingIndicators: logGForceIndeces,
                                              spots: log.samples
                                                  .map((e) => FlSpot(
                                                      e.time.toDouble(), unitConverters[UnitType.distFine]!(e.alt)))
                                                  .toList(),
                                              barWidth: 2,
                                              dotData: const FlDotData(show: false),
                                              color: Colors.blue),
                                        ] +
                                        log.gForceEvents
                                            .mapIndexed((i, e) => LineChartBarData(
                                                color: Colors.lightGreen,
                                                barWidth: 2,
                                                dotData: const FlDotData(show: false),
                                                spots: log.samples
                                                    .sublist(
                                                        log.timeToSampleIndex(DateTime.fromMillisecondsSinceEpoch(
                                                            e.timeRange.start.millisecondsSinceEpoch)),
                                                        log.timeToSampleIndex(DateTime.fromMillisecondsSinceEpoch(
                                                            e.timeRange.end.millisecondsSinceEpoch)))
                                                    .map(
                                                        (e) => FlSpot(e.time.toDouble(), unitConverters[UnitType.distFine]!(e.alt)))
                                                    .toList()))
                                            .toList(),
                                    titlesData: const FlTitlesData(
                                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, minIncluded: false, reservedSize: 40)),
                                        topTitles: AxisTitles(
                                          sideTitles: SideTitles(showTitles: false),
                                        ),
                                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)))),
                                duration: Duration.zero,
                              );
                            })),

                    // --- Speed Histogram
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Builder(builder: (context) {
                        final int interval = (log.speedHist.length / 15).ceil();
                        return BarChart(BarChartData(
                            borderData: FlBorderData(show: false),
                            barTouchData: BarTouchData(enabled: false),
                            gridData: const FlGridData(drawVerticalLine: false, drawHorizontalLine: false),
                            barGroups: log.speedHist
                                .mapIndexed((index, value) => BarChartGroupData(x: index, barRods: [
                                      BarChartRodData(
                                          toY: value.toDouble(),
                                          color: index % interval == 0 ? Colors.amberAccent : Colors.amber),
                                    ]))
                                .toList(),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                axisNameWidget: Text(getUnitStr(UnitType.speed)),
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  getTitlesWidget: (double value, TitleMeta meta) {
                                    return (value.round() % interval == 0)
                                        ? SideTitleWidget(
                                            meta: meta,
                                            child: Text(
                                              "${value.round() + log.speedHistOffset}",
                                            ),
                                          )
                                        : Container();
                                  },
                                ),
                              ),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            )));
                      }),
                    ),

                    // --- G-force timeline
                    (log.gForceEvents.isEmpty)
                        ? const Center(child: Text("No G-force events."))
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Expanded(
                                child: PageView.builder(
                                    controller: gForcePageController,
                                    itemCount: log.gForceEvents.length,
                                    onPageChanged: (int index) {
                                      // Map g-force event index to Geo sample index (times might not line up exactly)
                                      final middleTime = log.gForceEvents[index].center.time;
                                      gotoGeo(log.timeToSampleIndex(DateTime.fromMillisecondsSinceEpoch(middleTime)));
                                    },
                                    itemBuilder: (context, index) {
                                      bool showPeaks = false;
                                      return StatefulBuilder(
                                        builder: (context, setStateInner) {
                                          final slice = log.gForceSamples
                                              .sublist(log.gForceEvents[index].gForceIndeces.start,
                                                  log.gForceEvents[index].gForceIndeces.end)
                                              .toList();
                                          final keyPoints = douglasPeuckerTimestamped(slice, 0.3).toList();

                                          final peaksData = LineChartBarData(
                                              show: showPeaks,
                                              spots: keyPoints
                                                  .whereIndexed((i, e) =>
                                                      i < keyPoints.length - 1 &&
                                                      i > 0 &&
                                                      e.value > keyPoints[i - 1].value &&
                                                      e.value > keyPoints[i + 1].value)
                                                  .map((a) => FlSpot(a.time.toDouble(), a.value))
                                                  .toList(),
                                              dotData: FlDotData(
                                                getDotPainter: (p0, p1, p2, p3) =>
                                                    FlDotCirclePainter(radius: 3, color: Colors.red),
                                              ),
                                              isCurved: false,
                                              barWidth: 1,
                                              color: Colors.red);
                                          final valleysData = LineChartBarData(
                                            show: showPeaks,
                                            spots: keyPoints
                                                .whereIndexed((i, e) =>
                                                    i < keyPoints.length - 1 &&
                                                    i > 0 &&
                                                    e.value < keyPoints[i - 1].value &&
                                                    e.value < keyPoints[i + 1].value)
                                                .map((a) => FlSpot(a.time.toDouble(), a.value))
                                                .toList(),
                                            isCurved: false,
                                            barWidth: 1,
                                            color: Colors.blue,
                                            dotData: FlDotData(
                                              getDotPainter: (p0, p1, p2, p3) =>
                                                  FlDotCirclePainter(radius: 3, color: Colors.blue),
                                            ),
                                          );

                                          final maxG = log.maxG(index: index);
                                          final maxInt = (maxG + 0.5).ceil();
                                          final double timeInterval = max(
                                              2000,
                                              (log.gForceEvents[index].timeRange.duration.inMilliseconds / 1000)
                                                      .round() *
                                                  200);

                                          return GestureDetector(
                                            onLongPressDown: (details) {
                                              setStateInner(() => showPeaks = true);
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: Builder(builder: (context) {
                                                return LineChart(LineChartData(
                                                    minY: 0,
                                                    maxY: maxInt.toDouble(),
                                                    extraLinesData: ExtraLinesData(horizontalLines: [
                                                      if (maxG > 1.5)
                                                        HorizontalLine(
                                                            label: HorizontalLineLabel(
                                                              show: true,
                                                              labelResolver: (p0) => "Max ${maxG.toStringAsFixed(1)}G",
                                                            ),
                                                            y: maxG,
                                                            color: Colors.white,
                                                            strokeWidth: 1),
                                                    ]),
                                                    borderData: FlBorderData(show: false),
                                                    lineTouchData: LineTouchData(
                                                      touchSpotThreshold: 20,
                                                      touchTooltipData: LineTouchTooltipData(
                                                        getTooltipItems: (List<LineBarSpot> touchedSpots) {
                                                          return touchedSpots.map((LineBarSpot touchedSpot) {
                                                            if (touchedSpot.barIndex == 1) {
                                                              return LineTooltipItem(
                                                                touchedSpot.y.toStringAsFixed(1),
                                                                const TextStyle(
                                                                    color: Colors.redAccent,
                                                                    fontWeight: FontWeight.bold),
                                                              );
                                                            } else if (touchedSpot.barIndex == 2) {
                                                              return LineTooltipItem(
                                                                touchedSpot.y.toStringAsFixed(1),
                                                                const TextStyle(
                                                                    color: Colors.blue, fontWeight: FontWeight.bold),
                                                              );
                                                            }
                                                            return null;
                                                          }).toList();
                                                        },
                                                      ),
                                                      getTouchedSpotIndicator:
                                                          (LineChartBarData barData, List<int> spotIndexes) {
                                                        return spotIndexes.map((spotIndex) {
                                                          if (barData.spots[0] == peaksData.spots[0]) {
                                                            return TouchedSpotIndicatorData(
                                                                const FlLine(color: Colors.red, strokeWidth: 2),
                                                                FlDotData(
                                                                    getDotPainter: (spot, percent, barData, index) {
                                                              return FlDotCirclePainter(
                                                                  radius: 3,
                                                                  color: Colors.redAccent,
                                                                  strokeWidth: 2,
                                                                  strokeColor: Colors.red);
                                                            }));
                                                          } else if (barData.spots[0] == valleysData.spots[0]) {
                                                            return TouchedSpotIndicatorData(
                                                                const FlLine(color: Colors.blue, strokeWidth: 2),
                                                                FlDotData(
                                                                    getDotPainter: (spot, percent, barData, index) {
                                                              return FlDotCirclePainter(
                                                                  radius: 3,
                                                                  color: Colors.blueAccent,
                                                                  strokeWidth: 2,
                                                                  strokeColor: Colors.blue);
                                                            }));
                                                          } else {
                                                            return const TouchedSpotIndicatorData(
                                                              FlLine(color: Colors.transparent),
                                                              FlDotData(show: false),
                                                            );
                                                          }
                                                        }).toList();
                                                      },
                                                    ),
                                                    lineBarsData: [
                                                      LineChartBarData(
                                                          spots: slice
                                                              .map((a) => FlSpot(a.time.toDouble(), a.value))
                                                              .toList(),
                                                          isCurved: true,
                                                          barWidth: 1,
                                                          color: Colors.white,
                                                          dotData: const FlDotData(show: false),
                                                          aboveBarData: BarAreaData(
                                                              color: Colors.blue,
                                                              show: true,
                                                              cutOffY: 1,
                                                              applyCutOffY: true),
                                                          belowBarData: BarAreaData(
                                                              gradient: LinearGradient(
                                                                  begin: Alignment.bottomCenter,
                                                                  end: Alignment.topCenter,
                                                                  stops: [
                                                                    1 / maxInt,
                                                                    3 / maxInt,
                                                                    7 / maxInt
                                                                  ],
                                                                  colors: const [
                                                                    Colors.green,
                                                                    Colors.amber,
                                                                    Colors.red
                                                                  ]),
                                                              show: true,
                                                              color: Colors.amber,
                                                              cutOffY: 1,
                                                              applyCutOffY: true)),
                                                      peaksData,
                                                      valleysData,
                                                    ],
                                                    gridData: FlGridData(
                                                        drawVerticalLine: true,
                                                        drawHorizontalLine: true,
                                                        horizontalInterval: 1,
                                                        verticalInterval: timeInterval / 2),
                                                    titlesData: FlTitlesData(
                                                      bottomTitles: AxisTitles(
                                                        sideTitles: SideTitles(
                                                            maxIncluded: false,
                                                            interval: timeInterval,
                                                            getTitlesWidget: (value, meta) => Text.rich(richMinSec(
                                                                duration: Duration(
                                                                    milliseconds: value.round() -
                                                                        log
                                                                            .gForceSamples[log.gForceEvents[index]
                                                                                .gForceIndeces.start]
                                                                            .time))),
                                                            showTitles: true),
                                                      ),
                                                      topTitles: const AxisTitles(
                                                        sideTitles: SideTitles(showTitles: false),
                                                      ),
                                                      rightTitles: const AxisTitles(
                                                        sideTitles: SideTitles(showTitles: false),
                                                      ),
                                                      leftTitles: const AxisTitles(
                                                        sideTitles: SideTitles(interval: 1, showTitles: true),
                                                      ),
                                                    )));
                                              }),
                                            ),
                                          );
                                        },
                                      );
                                    }),
                              ),
                              SmoothPageIndicator(
                                controller: gForcePageController,
                                count: log.gForceEvents.length,
                                effect: const SlideEffect(activeDotColor: Colors.white),
                                onDotClicked: (index) => gForcePageController.jumpToPage(index),
                              ),
                              const SizedBox(
                                height: 20,
                              )
                            ],
                          ),

                    // --- Fuel
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment:
                              log.fuelReports.isEmpty ? MainAxisAlignment.center : MainAxisAlignment.start,
                          children: [
                            if (log.fuelReports.isNotEmpty)
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // --- Fuel Stats: title
                                    DefaultTextStyle(
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                          children: [
                                            const Text("Duration (min)"),
                                            Text("Burn Rate ($fuelRateStr)"),
                                            Text("Efficiency ($fuelEffStr)"),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // --- Fuel Stats: data
                                    Expanded(
                                      child: DefaultTextStyle(
                                        style: const TextStyle(fontSize: 18),
                                        child: Container(
                                          color: Colors.grey.shade800,
                                          // constraints: const BoxConstraints(maxHeight: 130),
                                          child: ListView(
                                              shrinkWrap: true,
                                              children: log.fuelStats
                                                  .mapIndexed((index, e) =>
                                                      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                                                        Text("${e.durationTime.inMinutes}"),
                                                        Text(printValue(UnitType.fuel, e.rate, decimals: 1) ?? "?"),
                                                        Text(printValue(UnitType.distCoarse,
                                                                e.mpl / unitConverters[UnitType.fuel]!(1),
                                                                decimals: 1) ??
                                                            "?")
                                                      ]))
                                                  .toList()),
                                        ),
                                      ),
                                    ),
                                    // --- Fuel Stats: summary
                                    if (log.sumFuelStat != null && log.fuelStats.length > 1)
                                      DefaultTextStyle(
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: SizedBox(
                                            height: 25,
                                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                                              const Text("---"),
                                              Text(printValue(UnitType.fuel, log.sumFuelStat!.rate) ?? "?"),
                                              Text(printValue(UnitType.distCoarse,
                                                      log.sumFuelStat!.mpl / unitConverters[UnitType.fuel]!(1)) ??
                                                  "?")
                                            ]),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                            // --- Add Fuel Report
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: ElevatedButton.icon(
                                  onPressed: () {
                                    editFuelReport(
                                            context,
                                            DateTime.fromMillisecondsSinceEpoch(log.samples[sampleIndex.value].time),
                                            null)
                                        .then((newReport) {
                                      if (newReport != null) {
                                        setState(() {
                                          log.insertFuelReport(newReport.time, newReport.amount,
                                              tolerance: const Duration(minutes: 1));
                                        });
                                      }
                                    });
                                  },
                                  label: const Text("Insert"),
                                  icon: const Stack(
                                    children: [
                                      Icon(
                                        Icons.local_gas_station,
                                        color: Colors.green,
                                        size: 30,
                                      ),
                                      Padding(
                                        padding: EdgeInsets.only(left: 3.5, top: 11),
                                        child: Icon(
                                          Icons.add,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ],
                                  )),
                            ),
                          ],
                        )),
                  ]),
            ),

            TabBar(labelPadding: const EdgeInsets.all(0), controller: tabController, tabs: const [
              Tab(icon: Icon(Icons.info), text: "Summary"),
              Tab(
                icon: Icon(Icons.area_chart),
                text: "Altitude",
              ),
              Tab(icon: Icon(Icons.speed), text: "Speed"),
              Tab(icon: Icon(Icons.g_mobiledata), text: "G-Force"),
              Tab(icon: Icon(Icons.local_gas_station), text: "Fuel"),
            ]),
          ],
        ),
      ),
    );
  }
}

// ==================================================================================
//
//    MISC UTILS
//
// ----------------------------------------------------------------------------------
class _ThumbShape extends RoundSliderThumbShape {
  final _indicatorShape = const PaddleSliderValueIndicatorShape();

  const _ThumbShape();

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    super.paint(
      context,
      center,
      activationAnimation: activationAnimation,
      enableAnimation: enableAnimation,
      sliderTheme: sliderTheme,
      value: value,
      textScaleFactor: textScaleFactor,
      sizeWithOverflow: sizeWithOverflow,
      isDiscrete: isDiscrete,
      labelPainter: labelPainter,
      parentBox: parentBox,
      textDirection: textDirection,
    );
    _indicatorShape.paint(
      context,
      center,
      activationAnimation: const AlwaysStoppedAnimation(1),
      enableAnimation: enableAnimation,
      labelPainter: labelPainter,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      value: value,
      textScaleFactor: 0.8,
      sizeWithOverflow: sizeWithOverflow,
      isDiscrete: isDiscrete,
      textDirection: textDirection,
    );
  }
}

class LabelFlag extends StatelessWidget {
  const LabelFlag({
    super.key,
    required this.direction,
    required this.color,
    required this.text,
  });

  final TextDirection direction;
  final Widget text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final flag = SizedBox(
        height: 40,
        child: VerticalDivider(
          color: color,
          width: 3,
          thickness: 3,
        ));

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (direction == TextDirection.ltr) flag,
        Card(
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(topRight: Radius.circular(10), bottomRight: Radius.circular(10))),
          color: color,
          margin: EdgeInsets.zero,
          child: Padding(padding: const EdgeInsets.all(4.0), child: text),
        ),
        if (direction != TextDirection.ltr) flag,
      ],
    );
  }
}
