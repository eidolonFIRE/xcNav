import 'dart:math';
import 'dart:ui';
import 'package:easy_localization/easy_localization.dart' as tr;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart' as intl;
import 'package:vector_math/vector_math_64.dart' as vector;

import 'package:xcnav/datadog.dart';
import 'package:xcnav/dialogs/confirm_log_crop.dart';
import 'package:xcnav/dialogs/edit_gear.dart';
import 'package:xcnav/dialogs/edit_fuel_report.dart';
import 'package:xcnav/dialogs/label_flag.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/log_view.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/elevation_replay.dart';
import 'package:xcnav/widgets/g_force_pages.dart';
import 'package:xcnav/widgets/log_summary.dart';
import 'package:xcnav/widgets/map_selector.dart';
import 'package:xcnav/widgets/speed_histogram.dart';
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
  MapTileSrc mapTileSrc = MapTileSrc.topo;
  bool hideWaypoints = false;
  double mapOpacity = 1.0;
  ValueNotifier<bool> isMapDialOpen = ValueNotifier(false);
  ValueNotifier<DateTime?> selectedTime = ValueNotifier(null);

  String? logKey;
  late FlightLog log;
  late LogView logView;
  bool logLoaded = false;

  double windowHeight = 400;

  late final TabController tabController;

  late final List<int> logGForceIndeces;
  final fuelScrollController = ScrollController();

  final chartTransformController = TransformationController();

  double mainDividerPosition = -1;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 5, vsync: this);
    chartTransformController.addListener(() {
      selectedTime.value = null;

      final mat4 = chartTransformController.value;
      final scale = mat4.getMaxScaleOnAxis();
      final offset = -mat4.getTranslation()[0];
      final pixelW = MediaQuery.of(context).size.width - 18;

      final start = log.startTime!.millisecondsSinceEpoch;
      final end = log.endTime!.millisecondsSinceEpoch;
      final duration = end - start;
      final width = (duration / scale).round();
      final offsetReal = (offset * width / pixelW).round();

      // debugPrint("scale: $scale  offset: ${(offset / scale).round()} offsetReal: ${(offsetReal / 1000).round()}  width: ${(width / 1000).round()}");

      logView.timeRange = DateTimeRange(
          start: DateTime.fromMillisecondsSinceEpoch(start + offsetReal),
          end: DateTime.fromMillisecondsSinceEpoch(start + offsetReal + width));
    });

    // (dateRange.start - log.startTime!.millisecondsSinceEpoch) * pixelW / (duration / scale) = offset
  }

  void setChartTransform(DateTimeRange dateRange) {
    selectedTime.value = null;

    final curTrans = chartTransformController.value.getTranslation();
    final pixelW = MediaQuery.of(context).size.width - 18;
    final scale = log.durationTime.inMilliseconds / dateRange.duration.inMilliseconds;
    chartTransformController.value.setFromTranslationRotationScale(
        vector.Vector3(
            -(dateRange.start.millisecondsSinceEpoch - log.startTime!.millisecondsSinceEpoch) *
                pixelW /
                (log.durationTime.inMilliseconds / scale),
            curTrans[1],
            curTrans[2]),
        vector.Quaternion.identity(),
        vector.Vector3(scale, 1, 1));
  }

  @override
  void didChangeDependencies() {
    if (!logLoaded) {
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, Object>;
      logKey ??= args["logKey"] as String;
      debugPrint("Loading log $logKey");

      log = logStore.logs[logKey]!;

      logView = LogView(log);

      if (log.goodFile) {
        logLoaded = true;
      } else {
        error("Error loading log in replay screen.", attributes: {"filename": log.filename});
      }
    }
    windowHeight = MediaQuery.of(context).size.height;
    if (mainDividerPosition < 0) {
      mainDividerPosition = (windowHeight - 80) * 0.5;
    }
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  void selectTime(double? time) {
    if (time != null) {
      selectedTime.value = DateTime.fromMillisecondsSinceEpoch(time.round());
    } else {
      selectedTime.value = null;
    }
  }

  void fitMap() {
    mapController.fitCamera(CameraFit.coordinates(
        coordinates: log.samples
            .sublist(logView.sampleIndexRange.start, logView.sampleIndexRange.end)
            .map((e) => e.latlng)
            .toList(),
        padding: EdgeInsets.all(50),
        minZoom: 4,
        maxZoom: 14));
  }

  void editFuelReport(BuildContext context, int reportIndex) {
    dialogEditFuelReport(
            context: context,
            time: log.fuelReports[reportIndex].time,
            amount: log.fuelReports[reportIndex].amount,
            validRange: log.timeRange!)
        .then((newReport) {
      setState(() {
        if (newReport != null) {
          if (newReport.amount == 0 && newReport.time.millisecondsSinceEpoch == 0) {
            // Report was deleted
            log.removeFuelReport(reportIndex);
          } else {
            // Edit fuel report amount
            log.updateFuelReport(reportIndex, newReport.amount, time: newReport.time);
          }
        }
      });
    });
  }

  void showCropCutSuggestion(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
                title: Text("Invalid Selection".tr()),
                content: Text("dialog_select_range_with_slider".tr()),
                actions: [
                  IconButton(
                      icon: const Icon(
                        Icons.check,
                        color: Colors.lightGreen,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                      })
                ]));
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("Build /logReplay");

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
                  case "crop":
                    if (logView.sampleIndexRange.start <= 2 && logView.sampleIndexRange.end >= log.samples.length - 3) {
                      showCropCutSuggestion(context);
                    } else {
                      confirmLogCrop(context,
                              trimStart: Duration(
                                  milliseconds:
                                      log.samples[logView.sampleIndexRange.start].time - log.samples.first.time),
                              trimEnd: Duration(
                                  milliseconds:
                                      -log.samples[logView.sampleIndexRange.end].time + log.samples.last.time))
                          .then((confirmed) {
                        setState(() {
                          if (confirmed ?? false) {
                            final newLog = log.cropLog(logView.sampleIndexRange);
                            logStore.updateLog(logKey!, newLog);
                            log = newLog;
                            logView.timeRange = DateTimeRange(start: newLog.startTime!, end: newLog.endTime!);
                          }
                        });
                      });
                    }
                    break;
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                PopupMenuItem(
                  value: "edit_gear",
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text("btn.Edit Gear".tr()),
                  ),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                    value: "crop",
                    child: ListTile(
                      leading: Icon(
                        Icons.crop,
                        size: 32,
                      ),
                      title: Text(
                        "btn.crop_log".tr(),
                        style: TextStyle(color: Colors.red),
                      ),
                    )),
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
                              initialCameraFit: CameraFit.bounds(
                                  bounds: log.getBounds(), padding: EdgeInsets.all(50), minZoom: 4, maxZoom: 14),
                              onMapReady: () {
                                setState(() {
                                  mapReady = true;
                                });
                              },
                              interactionOptions:
                                  const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
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

                              // Log line - base
                              PolylineLayer(polylines: [
                                Polyline(
                                    points: log.samples.map((e) => e.latlng).toList(),
                                    strokeWidth: 3,
                                    borderColor: Colors.black,
                                    // borderStrokeWidth: 1,
                                    color: Colors.amber,
                                    pattern: StrokePattern.dotted()
                                    // gradientColors: [Colors.amber, Colors.orange],
                                    )
                              ]),

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
                              ListenableBuilder(
                                  listenable: logView,
                                  builder: (context, _) {
                                    return PolylineLayer(polylines: [
                                      Polyline(
                                          points: log.samples
                                              .sublist(logView.sampleIndexRange.start, logView.sampleIndexRange.end)
                                              .map((e) => e.latlng)
                                              .toList(),
                                          strokeWidth: 4,
                                          borderColor: Colors.black,
                                          borderStrokeWidth: 1,
                                          color: Colors.amber
                                          // gradientColors: [Colors.amber, Colors.orange],
                                          )
                                    ]);
                                  }),

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
                                                // TODO - scrollToTime
                                                // logView.timeRange = (e.time);
                                              });
                                            },
                                            onLongPress: () {
                                              editFuelReport(context, index);
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

                              // --- "ME" marker if selected
                              ValueListenableBuilder<DateTime?>(
                                  valueListenable: selectedTime,
                                  builder: (context, time, _) {
                                    if (time != null) {
                                      final geo = log.samples[log.timeToSampleIndex(time)];
                                      return MarkerLayer(
                                        markers: [
                                          Marker(
                                            width: 40.0,
                                            height: 40.0,
                                            point: geo.latlng,
                                            child: Container(
                                              transformAlignment: const Alignment(0, 0),
                                              transform: Matrix4.rotationZ(geo.hdg),
                                              child: Image.asset("assets/images/red_arrow.png"),
                                            ),
                                          ),
                                        ],
                                      );
                                    } else {
                                      return Container();
                                    }
                                  }),
                            ]),

                        Align(
                          alignment: Alignment.topLeft,
                          child: DefaultTextStyle(
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                            child: ValueListenableBuilder<DateTime?>(
                                valueListenable: selectedTime,
                                builder: (context, time, _) {
                                  if (time == null) {
                                    return Container();
                                  } else {
                                    final geo = log.samples[log.timeToSampleIndex(time)];
                                    return Container(
                                        foregroundDecoration: BoxDecoration(
                                            border: Border.all(width: 0.5, color: Colors.black),
                                            borderRadius: const BorderRadius.all(Radius.circular(15))),
                                        child: ClipRRect(
                                            borderRadius: BorderRadius.circular(15),
                                            child: BackdropFilter(
                                                filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                                                child: Container(
                                                    color: Colors.white38,
                                                    child: Padding(
                                                      padding: const EdgeInsets.all(8.0),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          // --- Speed
                                                          Text.rich(TextSpan(children: [
                                                            WidgetSpan(
                                                                child: Icon(
                                                              Icons.speed,
                                                              size: 16,
                                                              color: Colors.black,
                                                            )),
                                                            TextSpan(text: " "),
                                                            richValue(UnitType.speed, geo.spd,
                                                                unitStyle: TextStyle(fontWeight: FontWeight.normal)),
                                                          ])),
                                                          // --- Altitude
                                                          Text.rich(TextSpan(children: [
                                                            TextSpan(
                                                                text: "MSL ",
                                                                style: TextStyle(fontWeight: FontWeight.normal)),
                                                            richValue(UnitType.distFine, geo.alt,
                                                                unitStyle: TextStyle(fontWeight: FontWeight.normal)),
                                                          ])),
                                                          if (geo.ground != null)
                                                            Text.rich(TextSpan(children: [
                                                              TextSpan(
                                                                  text: "AGL ",
                                                                  style: TextStyle(fontWeight: FontWeight.normal)),
                                                              richValue(UnitType.distFine, geo.alt - geo.ground!,
                                                                  unitStyle: TextStyle(fontWeight: FontWeight.normal)),
                                                            ])),
                                                          // --- Vario
                                                          Text.rich(TextSpan(children: [
                                                            WidgetSpan(
                                                                child: Icon(
                                                              Icons.height,
                                                              size: 16,
                                                              color: Colors.black,
                                                            )),
                                                            TextSpan(text: " "),
                                                            richValue(
                                                                UnitType.vario,
                                                                log
                                                                    .varioLogSmoothed[nearestIndex(
                                                                        log.varioLogSmoothed
                                                                            .map((e) => e.time)
                                                                            .toList(),
                                                                        time.millisecondsSinceEpoch)]
                                                                    .value,
                                                                unitStyle: TextStyle(fontWeight: FontWeight.normal)),
                                                          ])),
                                                        ],
                                                      ),
                                                    )))));
                                  }
                                }),
                          ),
                        ),

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
                    mainDividerPosition = min(windowHeight - 350, max(0, mainDividerPosition + event.delta.dy));
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
                      padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
                      child: LogSummary(log: log),
                    ),

                    // --- Elevation Plot
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevationReplay(
                          showVario: true,
                          logView: logView,
                          onSelectedGForce: (index) {
                            logView.timeRange = log.gForceEvents[index].timeRange;
                          },
                          onSelectedTime: selectTime,
                          transformController: chartTransformController,
                        )),

                    // --- Speed Histogram
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SpeedHistogram(
                          transformController: chartTransformController,
                          logView: logView,
                          onSelectedTime: selectTime,
                        )),

                    // --- G-force event pages
                    (log.gForceEvents.isEmpty)
                        ? Center(child: Text("empty_list".tr()))
                        : Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: GForcePages(
                              onSelectedTime: selectTime,
                              onPageChanged: (index) {
                                setState(() {
                                  logView.timeRange = log.gForceEvents[index].timeRange;
                                  setChartTransform(logView.timeRange);
                                });
                              },
                              transformController: chartTransformController,
                              logView: logView,
                            ),
                          ),

                    // --- Fuel
                    DefaultTextStyle(
                      style: const TextStyle(fontSize: 18),
                      child: Container(
                        color: Colors.grey.shade800,
                        child: Scrollbar(
                          controller: fuelScrollController,
                          trackVisibility: true,
                          thumbVisibility: true,
                          child: ListView(
                              controller: fuelScrollController,
                              shrinkWrap: true,
                              children:
                                  // Start of flight
                                  <Widget>[TimeCard(time: log.startTime, text: "Launch".tr())] +

                                      // Fuel reports
                                      log.fuelStats.expandIndexed<Widget>((index, e) sync* {
                                        yield Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            FuelEntryCard(
                                                log: log,
                                                reportIndex: index,
                                                onEdit: (reportIndex) => editFuelReport(context, reportIndex)),
                                            Container(),
                                            Container(),
                                          ],
                                        );

                                        yield Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                                          Container(),
                                          Container(),
                                          SizedBox(
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                // Vertical line
                                                Container(
                                                  width: 1,
                                                  height: 50,
                                                  color: Colors.blue,
                                                ),
                                                // Circle
                                                Container(
                                                  width: 30,
                                                  height: 30,
                                                  decoration: BoxDecoration(
                                                      color: Colors.grey.shade800,
                                                      border: Border.all(color: Colors.blue, width: 1),
                                                      borderRadius: BorderRadius.circular(20)),
                                                ),
                                                IconButton(
                                                    iconSize: 26,
                                                    padding: EdgeInsets.zero,
                                                    onPressed: () => dialogEditFuelReport(
                                                                context: context,
                                                                time: DateTime.fromMillisecondsSinceEpoch(((log
                                                                                .fuelReports[index]
                                                                                .time
                                                                                .millisecondsSinceEpoch +
                                                                            log.fuelReports[index + 1].time
                                                                                .millisecondsSinceEpoch) /
                                                                        2)
                                                                    .round()),
                                                                amount: null,
                                                                validRange: log.timeRange!)
                                                            .then((newReport) {
                                                          if (newReport != null) {
                                                            setState(() {
                                                              log.insertFuelReport(newReport.time, newReport.amount,
                                                                  tolerance: const Duration(minutes: 1));
                                                            });
                                                          }
                                                        }),
                                                    color: Colors.blue,
                                                    visualDensity: VisualDensity.compact,
                                                    icon: const Icon(Icons.add, color: Colors.white)),
                                              ],
                                            ),
                                          ),
                                          Container(),
                                          StatCard(
                                            stat: e,
                                          ),
                                          Container()
                                        ]);
                                      }).toList() +
                                      [
                                        // Final report
                                        if (log.fuelReports.isNotEmpty)
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                            children: [
                                              FuelEntryCard(
                                                  log: log,
                                                  reportIndex: log.fuelReports.length - 1,
                                                  onEdit: (reportIndex) => editFuelReport(context, reportIndex)),
                                              Container(),
                                              Container(),
                                            ],
                                          ),
                                        if (log.fuelReports.length < 2)
                                          IconButton(
                                              onPressed: () => dialogEditFuelReport(
                                                          context: context,
                                                          time: log.fuelReports.isEmpty ? log.startTime! : log.endTime!,
                                                          amount: null,
                                                          validRange: log.timeRange!)
                                                      .then((newReport) {
                                                    if (newReport != null) {
                                                      setState(() {
                                                        log.insertFuelReport(newReport.time, newReport.amount,
                                                            tolerance: const Duration(minutes: 1));
                                                      });
                                                    }
                                                  }),
                                              color: Colors.blue,
                                              visualDensity: VisualDensity.compact,
                                              icon: const Icon(Icons.add, color: Colors.white, size: 26)),
                                        // End of flight
                                        TimeCard(time: log.endTime, text: "Landing".tr()),
                                      ]),
                        ),
                      ),
                    ),
                  ]),
            ),

            TabBar(labelPadding: const EdgeInsets.all(0), controller: tabController, tabs: [
              Tab(icon: Icon(Icons.info), text: "Summary".tr()),
              Tab(
                icon: Icon(Icons.area_chart),
                text: "Altitude".tr(),
              ),
              Tab(icon: Icon(Icons.speed), text: "Speed".tr()),
              Tab(icon: Icon(Icons.g_mobiledata), text: "G-Force".tr()),
              Tab(icon: Icon(Icons.local_gas_station), text: "Fuel".tr()),
            ]),
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.stat,
  });

  final FuelStat stat;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Card(
        color: Colors.grey.shade600,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        child: SizedBox(
          width: 180,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: printValue(UnitType.fuel, stat.rate, decimals: 1) ?? "?", style: TextStyle(fontSize: 16)),
                  TextSpan(text: fuelRateStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade300))
                ])),
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text:
                          printValue(UnitType.distCoarse, stat.mpl / unitConverters[UnitType.fuel]!(1), decimals: 1) ??
                              "?",
                      style: TextStyle(fontSize: 16)),
                  TextSpan(text: fuelEffStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade300))
                ])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TimeCard extends StatelessWidget {
  const TimeCard({
    super.key,
    this.time,
    this.text,
  });

  final String? text;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: DefaultTextStyle(
        style: TextStyle(color: Colors.grey, fontSize: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                time != null ? intl.DateFormat("h:mm a").format(time!) : "?",
              ),
            ),
            if (text != null) Padding(padding: const EdgeInsets.all(8), child: Text(text!))
          ],
        ),
      ),
    );
  }
}

class FuelEntryCard extends StatelessWidget {
  final FlightLog log;
  final int reportIndex;
  final void Function(int index)? onEdit;

  const FuelEntryCard({super.key, required this.log, required this.reportIndex, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Card(
        margin: const EdgeInsets.all(0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        color: Colors.blue,
        child: SizedBox(
          width: 200,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(),
            Text(intl.DateFormat("h:mm a").format(log.fuelReports[reportIndex].time)),
            Text.rich(TextSpan(children: [
              // Icon
              WidgetSpan(child: Icon(Icons.local_gas_station, size: 18)),
              // Fuel amount
              richValue(UnitType.fuel, log.fuelReports[reportIndex].amount, decimals: 1),
            ])),
            IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: () => onEdit?.call(reportIndex),
                icon: Icon(Icons.edit)),
          ]),
        ),
      ),
    );
  }
}
