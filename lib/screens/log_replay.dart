import 'dart:math';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:collection/collection.dart';

import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';
import 'package:xcnav/widgets/elevation_plot.dart';
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

  final lowerStyle = TextStyle(color: Colors.black, fontSize: 20);
  final TextStyle unitStyle = TextStyle(fontSize: 12, color: Colors.black87, fontStyle: FontStyle.italic);

  late final TabController tabController;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    log ??= ModalRoute.of(context)!.settings.arguments as FlightLog;

    return Scaffold(
      appBar: AppBar(title: Text("Replay:  ${log?.title}")),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          // --- Map
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
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
                            for (final each in log!.waypoints) {
                              mapBounds.extendBounds(LatLngBounds.fromPoints(each.latlng));
                            }
                            mapBounds.pad(0.2);
                            mapController.fitBounds(mapBounds);
                          }
                        });
                      },
                      interactiveFlags:
                          InteractiveFlag.all & (northLock ? ~InteractiveFlag.rotate : InteractiveFlag.all),
                      // center: Provider.of<MyTelemetry>(context, listen: false).geo.latlng,
                      // zoom: 12.0,
                      // onTap: (tapPosition, point) => onMapTap(context, point),
                      // onLongPress: (tapPosition, point) => onMapLongPress(context, point),
                      onPositionChanged: (mapPosition, hasGesture) {
                        if (hasGesture) {
                          isMapDialOpen.value = false;
                          // if (focusMode == FocusMode.me || focusMode == FocusMode.group) {
                          //   // --- Unlock any focus lock
                          //   setFocusMode(FocusMode.unlocked);
                          // }
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
                        // onTap: (p0, tapPosition) {
                        //   // Select this path waypoint
                        //   if (plan.selectedWp == p0.tag) {
                        //     plan.waypoints[p0.tag]?.toggleDirection();
                        //   }
                        //   plan.selectedWp = p0.tag;
                        // },
                        // onLongPress: ((p0, tapPosition) {
                        //   // Start editing path waypoint
                        //   if (plan.waypoints.containsKey(p0.tag)) {
                        //     beginEditingLine(plan.waypoints[p0.tag]!);
                        //   }
                        // }
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
                                  // NOTE: regular waypoints are no longer draggable. But, this is how it was done before.
                                  // updateMapNearEdge: true,
                                  // useLongPress: true,
                                  // onTap: (_) => plan.selectedWp = e.id,
                                  // onLongDragEnd: (p0, p1) => {
                                  //       plan.moveWaypoint(e.id, [p1])
                                  //     },
                                  // rotateMarker: true,
                                  // onLongPress: (_) {
                                  //   editingWp = e.id;
                                  //   debugPrint("Context Menu for Waypoint ${e.name}");
                                  // },
                                  builder: (context) => WaypointMarker(e, 60 * 0.8)))
                              .toList()),

                      // --- Log Line
                      PolylineLayer(polylines: [
                        Polyline(
                            points: log!.samples.map((e) => e.latlng).toList(),
                            strokeWidth: 3,
                            color: Colors.red,
                            isDotted: true)
                      ]),

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
                                            valueStyle: lowerStyle,
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

          Expanded(
            child: TabBarView(physics: const NeverScrollableScrollPhysics(), controller: tabController, children: [
              // --- Elevation Plot
              Listener(
                  onPointerMove: (pos) {
                    sampleIndex.value = max(
                        0,
                        min(
                            log!.samples.length - 1,
                            ((pos.position.dx - 8) / (MediaQuery.of(context).size.width - 16) * log!.samples.length)
                                .floor()));
                    // debugPrint("Sample Index: $sampleIndex");
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRect(
                          child: ValueListenableBuilder<int>(
                              valueListenable: sampleIndex,
                              builder: (context, value, _) {
                                return CustomPaint(
                                  // willChange: true,
                                  painter: ElevationPlotPainter(log!.samples, [], 100,
                                      showPilotIcon: false, labelIndex: value),
                                );
                              }),
                        ),
                        if (sampleIndex == null)
                          const Align(
                            alignment: Alignment.center,
                            child: Text.rich(
                              TextSpan(children: [
                                WidgetSpan(
                                    child: Icon(
                                  Icons.touch_app,
                                  size: 26,
                                )),
                                TextSpan(text: "  Scrub Timeline")
                              ]),
                              style: TextStyle(fontSize: 18, shadows: [Shadow(color: Colors.black, blurRadius: 20)]),
                            ),
                          ),
                      ],
                    ),
                  )),

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
            ]),
          ),

          TabBar(controller: tabController, tabs: const [
            Tab(
              icon: Icon(Icons.area_chart),
              text: "Altitude",
            ),
            Tab(icon: Icon(Icons.speed), text: "Speed"),
          ]),
        ],
      ),
    );
  }
}
