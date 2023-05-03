import 'dart:math';
import 'dart:ui';
import 'package:intl/intl.dart' as intl;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:collection/collection.dart';
import 'package:xcnav/dialogs/fuel_report_dialog.dart';

import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';
import 'package:xcnav/widgets/elevation_plot.dart';
import 'package:xcnav/widgets/log_summary.dart';
import 'package:xcnav/widgets/map_button.dart';
import 'package:xcnav/widgets/map_selector.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

class LogReplay extends StatefulWidget {
  const LogReplay({Key? key}) : super(key: key);

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

  FlightLog? log;

  ValueNotifier<int> sampleIndex = ValueNotifier(0);
  bool hasScrubbed = false;

  final lowerStyle = const TextStyle(color: Colors.black, fontSize: 20);
  final TextStyle unitStyle = const TextStyle(fontSize: 12, color: Colors.black87, fontStyle: FontStyle.italic);

  late final TabController tabController;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    log ??= ModalRoute.of(context)!.settings.arguments as FlightLog;

    return WillPopScope(
      onWillPop: () {
        if (log != null && log!.goodFile && log!.unsaved) {
          log!.save();
        }
        return Future.value(true);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(title: Text("Replay:  ${log?.title}")),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            // --- Map
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Stack(children: [
                if (log != null)
                  FlutterMap(
                      key: mapKey,
                      mapController: mapController,
                      options: MapOptions(
                        absorbPanEventsOnScrollables: false,
                        onMapReady: () {
                          setState(() {
                            mapReady = true;
                            if (log != null) {
                              final mapBounds = LatLngBounds.fromPoints(log!.samples.map((e) => e.latlng).toList());
                              mapBounds.pad(0.2);
                              mapController.fitBounds(mapBounds);
                            }
                          });
                        },
                        interactiveFlags:
                            InteractiveFlag.all & (northLock ? ~InteractiveFlag.rotate : InteractiveFlag.all),
                        onPositionChanged: (mapPosition, hasGesture) {
                          if (hasGesture) {
                            isMapDialOpen.value = false;
                          }
                        },
                      ),
                      children: [
                        getMapTileLayer(mapTileSrc, mapOpacity),

                        // Airspace overlay
                        if (mapTileSrc != MapTileSrc.sectional) getMapTileLayer(MapTileSrc.airspace, 1),
                        if (mapTileSrc != MapTileSrc.sectional) getMapTileLayer(MapTileSrc.airports, 1),

                        // Waypoints: paths
                        PolylineLayer(
                          // pointerDistanceTolerance: 30,
                          polylineCulling: true,
                          polylines: log!.waypoints
                              .where((value) => value.latlng.length > 1)
                              .map((e) => Polyline(points: e.latlng, strokeWidth: 6.0, color: e.getColor()))
                              .toList(),
                        ),

                        // Waypoint markers
                        MarkerLayer(
                            markers: log!.waypoints
                                .where((e) => e.latlng.length == 1)
                                .map((e) => Marker(
                                    point: e.latlng[0],
                                    height: 60 * 0.8,
                                    width: 40 * 0.8,
                                    rotate: true,
                                    anchorPos: AnchorPos.exactly(Anchor(20 * 0.8, 0)),
                                    rotateOrigin: const Offset(0, 30 * 0.8),
                                    builder: (context) => WaypointMarker(e, 60 * 0.8)))
                                .toList()),

                        // --- Log Line
                        PolylineLayer(polylines: [
                          Polyline(
                              points: log!.samples.map((e) => e.latlng).toList(),
                              strokeWidth: 4,
                              color: Colors.red,
                              isDotted: true)
                        ]),

                        // --- Fuel reports
                        MarkerLayer(
                          markers: log!.fuelReports
                              .mapIndexed((index, e) => Marker(
                                    anchorPos: AnchorPos.align(AnchorAlign.right),
                                    height: 40,
                                    width: 60,
                                    point: log!.samples[log!.timeToSampleIndex(e.time)].latlng,
                                    builder: (context) {
                                      return Container(
                                        transform: Matrix4.translationValues(-2, -20, 0),
                                        child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                sampleIndex.value = log!.timeToSampleIndex(e.time);
                                              });
                                            },
                                            onLongPress: () {
                                              fuelReportDialog(context, e.time, e.amount).then((newReport) {
                                                setState(() {
                                                  if (newReport != null) {
                                                    if (newReport.amount == 0 &&
                                                        newReport.time.millisecondsSinceEpoch == 0) {
                                                      // Report was deleted
                                                      log!.removeFuelReport(index);
                                                    } else {
                                                      // Edit fuel report amount
                                                      log!.updateFuelReport(index, newReport.amount);
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
                                                color: Colors.blue)),
                                      );
                                    },
                                  ))
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
                                    point: log!.samples[value].latlng,
                                    builder: (ctx) => Container(
                                      transformAlignment: const Alignment(0, 0),
                                      transform: Matrix4.rotationZ(log!.samples[value].hdg),
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
                if (log != null)
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
                                      .format(DateTime.fromMillisecondsSinceEpoch(log!.samples[index].time)),
                                  value: (log!.samples[index].time - log!.startTime!.millisecondsSinceEpoch) /
                                      log!.durationTime.inMilliseconds,
                                  onChanged: (value) {
                                    sampleIndex.value = max(
                                        0,
                                        min(
                                            log!.samples.length - 1,
                                            log!.timeToSampleIndex(log!.startTime!.add(Duration(
                                                milliseconds: (value * log!.durationTime.inMilliseconds).round())))));
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
                        fuelReportDialog(context,
                                DateTime.fromMillisecondsSinceEpoch(log!.samples[sampleIndex.value].time), null)
                            .then((newReport) {
                          if (newReport != null) {
                            setState(() {
                              log!.insertFuelReport(newReport.amount, newReport.time);
                            });
                          }
                        });
                      },
                      selected: false,
                      child: Stack(
                        children: const [
                          Icon(
                            Icons.local_gas_station,
                            color: Colors.blue,
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
                                          Text.rich(richValue(UnitType.speed, log!.samples[value].spd,
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
                                            log!.samples[value].alt,
                                            valueStyle: lowerStyle,
                                            unitStyle: unitStyle,
                                            unitTag: "MSL",
                                            isPrimary: false,
                                          ),
                                          if (log!.samples[value].ground != null)
                                            Altimeter(
                                              log!.samples[value].ground != null
                                                  ? log!.samples[value].alt - log!.samples[value].ground!
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
                                ElevationPlotPainter(log!.samples, [], 100, showPilotIcon: false, labelIndex: value),
                          );
                        }),
                  ),
                ),

                // --- Speed Histogram
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Builder(builder: (context) {
                    final int interval = (log!.speedHist.length / 15).ceil();
                    return BarChart(BarChartData(
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(enabled: false),
                        gridData: FlGridData(drawVerticalLine: false, drawHorizontalLine: false),
                        barGroups: log!.speedHist
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
                                          "${value.round() + log!.speedHistOffset}",
                                        ),
                                      )
                                    : Container();
                              },
                            ),
                          ),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        )));
                  }),
                ),

                // --- Summary
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: LogSummary(log: log!),
                ),

                // --- Fuel
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: log!.fuelReports.isEmpty
                      ? const Center(
                          child: Text("No fuel reports added."),
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
                                    Text("Burn Rate (${getUnitStr(UnitType.fuel)}/hr)"),
                                    Text(
                                        "Efficiency (${getUnitStr(UnitType.distCoarse)}/${getUnitStr(UnitType.fuel)})"),
                                  ],
                                ),
                              ),
                            ),
                            // --- Fuel Stats: data
                            DefaultTextStyle(
                              style: const TextStyle(fontSize: 18),
                              child: Container(
                                color: Colors.grey.shade800,
                                constraints: const BoxConstraints(maxHeight: 130),
                                child: ListView(
                                    shrinkWrap: true,
                                    children: log!.fuelStats
                                        .map((e) => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                                              Text("${e.durationTime.inMinutes}"),
                                              Text(unitConverters[UnitType.fuel]!(e.rate).toStringAsFixed(1)),
                                              Text(unitConverters[UnitType.distCoarse]!(
                                                      e.mpl / unitConverters[UnitType.fuel]!(1))
                                                  .toStringAsFixed(1))
                                            ]))
                                        .toList()),
                              ),
                            ),
                            // --- Fuel Stats: summary
                            if (log!.sumFuelStat != null && log!.fuelStats.length > 1)
                              DefaultTextStyle(
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: SizedBox(
                                    height: 25,
                                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                                      const Text("---"),
                                      Text(unitConverters[UnitType.fuel]!(log!.sumFuelStat!.rate).toStringAsFixed(1)),
                                      Text(unitConverters[UnitType.distCoarse]!(
                                              log!.sumFuelStat!.mpl / unitConverters[UnitType.fuel]!(1))
                                          .toStringAsFixed(1))
                                    ]),
                                  ),
                                ),
                              )
                          ],
                        ),
                ),
              ]),
            ),

            TabBar(controller: tabController, tabs: const [
              Tab(
                icon: Icon(Icons.area_chart),
                text: "Altitude",
              ),
              Tab(icon: Icon(Icons.speed), text: "Speed"),
              Tab(icon: Icon(Icons.info), text: "Summary"),
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
    Key? key,
    required this.direction,
    required this.color,
    required this.text,
  }) : super(key: key);

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
