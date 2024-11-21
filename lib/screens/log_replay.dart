import 'dart:math';
import 'dart:ui';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart' as intl;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:collection/collection.dart';

import 'package:xcnav/dialogs/confirm_log_trim.dart';
import 'package:xcnav/dialogs/edit_gear.dart';
import 'package:xcnav/dialogs/edit_fuel_report.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';
import 'package:xcnav/widgets/elevation_plot.dart';
import 'package:xcnav/widgets/log_summary.dart';
import 'package:xcnav/widgets/map_button.dart';
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
  double mapOpacity = 1.0;
  ValueNotifier<bool> isMapDialOpen = ValueNotifier(false);

  String? logKey;

  ValueNotifier<int> sampleIndex = ValueNotifier(0);
  bool hasScrubbed = false;

  final lowerStyle = const TextStyle(color: Colors.black, fontSize: 20);
  final TextStyle unitStyle = const TextStyle(fontSize: 12, color: Colors.black87, fontStyle: FontStyle.italic);

  late final TabController tabController;

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

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, Object>;
    logKey ??= args["logKey"] as String;

    final log = logStore.logs[logKey]!;

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
                            sampleIndex.value = 0;
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
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Stack(children: [
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
                          flags: InteractiveFlag.all & (northLock ? ~InteractiveFlag.rotate : InteractiveFlag.all)),
                      onPositionChanged: (mapPosition, hasGesture) {
                        if (hasGesture) {
                          isMapDialOpen.value = false;
                        }
                      },
                    ),
                    children: [
                      Opacity(opacity: mapOpacity, child: getMapTileLayer(mapTileSrc)),

                      // Waypoints: paths
                      PolylineLayer(
                        polylines: log.waypoints
                            .where((value) => value.latlng.length > 1)
                            .map((e) => Polyline(points: e.latlng, strokeWidth: 6.0, color: e.getColor()))
                            .toList(),
                      ),

                      // Waypoint markers
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
                                        sampleIndex.value = log.timeToSampleIndex(e.time);
                                      });
                                    },
                                    onLongPress: () {
                                      editFuelReport(context, e.time, e.amount).then((newReport) {
                                        setState(() {
                                          if (newReport != null) {
                                            if (newReport.amount == 0 && newReport.time.millisecondsSinceEpoch == 0) {
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

                      // "ME" Live Location Marker
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
                                              milliseconds: (value * log.durationTime.inMilliseconds).round())))));
                                }),
                          ));
                    }),

                // --- Add Fuel Report
                Positioned(
                  left: 10,
                  bottom: 90,
                  child: MapButton(
                      size: 45,
                      onPressed: () {
                        editFuelReport(
                                context, DateTime.fromMillisecondsSinceEpoch(log.samples[sampleIndex.value].time), null)
                            .then((newReport) {
                          if (newReport != null) {
                            setState(() {
                              log.insertFuelReport(newReport.time, newReport.amount);
                            });
                          }
                        });
                      },
                      selected: false,
                      child: const Stack(
                        children: [
                          Icon(
                            Icons.local_gas_station,
                            color: Colors.black,
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

            /// ====================================
            ///
            ///     Lower Half
            ///
            /// ------------------------------------
            Expanded(
              child: TabBarView(physics: const NeverScrollableScrollPhysics(), controller: tabController, children: [
                // --- Summary
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: LogSummary(log: log),
                ),

                // --- Elevation Plot
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRect(
                    child: ValueListenableBuilder<int>(
                        valueListenable: sampleIndex,
                        builder: (context, value, _) {
                          return CustomPaint(
                            // willChange: true,
                            painter:
                                ElevationPlotPainter(log.samples, [], 100, showPilotIcon: false, labelIndex: value),
                          );
                        }),
                  ),
                ),

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
                                        axisSide: meta.axisSide,
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
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Builder(builder: (context) {
                    final samples = log.samples.where((a) => a.gForce != null);

                    if (samples.isNotEmpty) {
                      final max = log.maxG()!;
                      final maxInt = max.round() + 1;
                      final sustained = log.maxGSustained()!;
                      return LineChart(LineChartData(
                          minY: 0,
                          maxY: maxInt.toDouble(),
                          extraLinesData: ExtraLinesData(horizontalLines: [
                            if (max > 1.5)
                              HorizontalLine(
                                  label: HorizontalLineLabel(
                                    show: true,
                                    labelResolver: (p0) => "Max ${max.toStringAsFixed(1)}G",
                                  ),
                                  y: max,
                                  color: Colors.white,
                                  strokeWidth: 1),
                            if (sustained > 1.5)
                              HorizontalLine(
                                  label: HorizontalLineLabel(
                                    show: true,
                                    labelResolver: (p0) => "Sustained ${sustained.toStringAsFixed(1)}G for 10s",
                                  ),
                                  y: sustained,
                                  color: Colors.white,
                                  strokeWidth: 1)
                          ]),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                                spots: samples.map((a) => FlSpot(a.time.toDouble(), a.gForce!)).toList(),
                                isCurved: false,
                                barWidth: 1,
                                color: Colors.white,
                                dotData: const FlDotData(show: false),
                                aboveBarData:
                                    BarAreaData(color: Colors.blue, show: true, cutOffY: 1, applyCutOffY: true),
                                belowBarData: BarAreaData(
                                    gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        stops: [1 / maxInt, 3 / maxInt, 7 / maxInt],
                                        colors: const [Colors.green, Colors.amber, Colors.red]),
                                    show: true,
                                    color: Colors.amber,
                                    cutOffY: 1,
                                    applyCutOffY: true))
                          ],
                          lineTouchData: const LineTouchData(enabled: false),
                          gridData: const FlGridData(
                              drawVerticalLine: false, drawHorizontalLine: true, horizontalInterval: 2),
                          titlesData: const FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(interval: 1, showTitles: true),
                            ),
                          )));
                    } else {
                      return const Center(child: Text("No Data"));
                    }
                  }),
                ),

                // --- Fuel
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: log.fuelReports.isEmpty
                      ? const Center(
                          child: Text("No fuel reports added..."),
                        )
                      : Column(
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
                            DefaultTextStyle(
                              style: const TextStyle(fontSize: 18),
                              child: Expanded(
                                child: Container(
                                  color: Colors.grey.shade800,
                                  // constraints: const BoxConstraints(maxHeight: 130),
                                  child: ListView(
                                      shrinkWrap: true,
                                      children: log.fuelStats
                                          .map((e) => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                                                Text("${e.durationTime.inMinutes}"),
                                                Text(printValue(UnitType.fuel, e.rate, decimals: 1) ?? "?"),
                                                Text(printValue(
                                                        UnitType.distCoarse, e.mpl / unitConverters[UnitType.fuel]!(1),
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
                              )
                          ],
                        ),
                ),
              ]),
            ),

            TabBar(labelPadding: const EdgeInsets.all(0), controller: tabController, tabs: const [
              Tab(icon: Icon(Icons.info), text: "Summary"),
              Tab(
                icon: Icon(Icons.area_chart),
                text: "Altitude",
              ),
              Tab(icon: Icon(Icons.speed), text: "Speed"),
              Tab(icon: Icon(Icons.g_mobiledata), text: "G force"),
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
