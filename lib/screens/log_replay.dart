import 'dart:math';
import 'dart:ui';
import 'package:easy_localization/easy_localization.dart' as tr;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' as intl;
// ignore: depend_on_referenced_packages
import 'package:vector_math/vector_math_64.dart' as vector;

import 'package:xcnav/datadog.dart';
import 'package:xcnav/dialogs/confirm_log_crop.dart';
import 'package:xcnav/dialogs/edit_gear.dart';
import 'package:xcnav/dialogs/edit_fuel_report.dart';
import 'package:xcnav/dialogs/label_flag.dart';
import 'package:xcnav/dialogs/rename_dialog.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/log_view.dart';
import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/models/map_shapes.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/views/map/map_layers.dart';
import 'package:xcnav/views/map/map_symbols.dart';
import 'package:xcnav/views/map/xc_map.dart';
import 'package:xcnav/widgets/elevation_replay.dart';
import 'package:xcnav/widgets/engine_replay.dart';
import 'package:xcnav/widgets/g_force_pages.dart';
import 'package:xcnav/widgets/log_summary.dart';
import 'package:xcnav/widgets/map_selector.dart';
import 'package:xcnav/widgets/speed_histogram.dart';

class LogReplay extends StatefulWidget {
  const LogReplay({super.key});

  @override
  State<LogReplay> createState() => _LogReplayState();
}

class _LogReplayState extends State<LogReplay> with SingleTickerProviderStateMixin {
  final mapController = XcMapController();
  MapTileSrc mapTileSrc = MapTileSrc.topo;
  bool hideWaypoints = false;
  double mapOpacity = 1.0;
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
    tabController = TabController(length: 6, vsync: this);
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
    mapController.fitBounds(
        LatLngBounds.fromPoints(log.samples
            .sublist(logView.sampleIndexRange.start, logView.sampleIndexRange.end)
            .map((e) => e.latlng)),
        padding: EdgeInsets.all(50),
        minZoom: 3,
        maxZoom: 13);
  }

  void editFuelReport(BuildContext context, int reportIndex) {
    dialogEditFuelReport(
            context: context,
            time: log.fuelReportController.fuelReports[reportIndex].time,
            amount: log.fuelReportController.fuelReports[reportIndex].amount,
            validRange: log.timeRange!,
            toDisplayTime: log.toOriginalTime,
            fromDisplayTime: log.fromOriginalTime)
        .then((newReport) {
      setState(() {
        if (newReport != null) {
          if (newReport.amount == 0 && newReport.time.millisecondsSinceEpoch == 0) {
            // Report was deleted
            log.fuelReportController.removeFuelReport(reportIndex);
          } else {
            // Edit fuel report amount
            log.fuelReportController.updateFuelReport(reportIndex, newReport.amount, time: newReport.time);
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

    bool hasxc170 = (log.bleDevicesJson?["xc170"]?["datas"]["telemetry"]?["rpm"]?["data"]?.length ?? 0) > 0;
    bool hasRunLeader = (log.bleDevicesJson?["runleader"]?["datas"]?["telemetry"]?["rpm"]?["data"]?.length ?? 0) > 0;
    bool hasSp140 = (log.bleDevicesJson?["sp140"]?["datas"]?["telemetry"]?["power"]?["data"]?.length ?? 0) > 0;
    bool showEngineTab = hasxc170 || hasRunLeader || hasSp140;

    return PopScope(
      onPopInvokedWithResult: (_, __) {
        ScaffoldMessenger.of(context).clearMaterialBanners();
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
                  case "rename":
                    showRenameDialog(context, text: log.customTitle).then((value) {
                      setState(() {
                        if (value != null) {
                          log.customTitle = value;
                        }
                      });
                    });

                    break;
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
                  case "xc170":
                    Navigator.pushNamed(context, "/xc170Report", arguments: {"logKey": logKey!});
                    break;
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                PopupMenuItem(
                    value: "rename",
                    child: ListTile(
                        leading: Icon(
                          Icons.edit,
                        ),
                        title: Text("btn.Rename".tr()))),
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
                if (hasxc170) PopupMenuDivider(),
                if (hasxc170)
                  PopupMenuItem(
                      value: "xc170",
                      child: ListTile(
                        leading: Icon(
                          Icons.bluetooth,
                          size: 32,
                        ),
                        title: Text("Xc170 Report"),
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
                        ListenableBuilder(
                            // The "ME" marker follows the selected time
                            listenable: Listenable.merge([logView, selectedTime]),
                            builder: (context, _) => XcMap(
                                    controller: mapController,
                                    tileSrc: mapTileSrc,
                                    opacity: mapOpacity,
                                    initialBounds: log.getBounds(),
                                    initialPadding: EdgeInsets.all(50),
                                    initialMaxZoom: 13,
                                    rotateGestures: false,
                                    onLongPress: (latlng, _) {
                                      // Copy latlng to clipboard
                                      Clipboard.setData(ClipboardData(
                                          text:
                                              "${latlng.latitude.toStringAsFixed(6)},${latlng.longitude.toStringAsFixed(8)}"));
                                      ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
                                        padding: EdgeInsets.all(20),
                                        content: Text("Lat,Long copied to clipboard"),
                                        leading: Icon(Icons.copy),
                                        backgroundColor: Colors.green,
                                        actions: <Widget>[
                                          TextButton(
                                              onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                                              child: Text('DISMISS')),
                                        ],
                                      ));
                                    },
                                    shapes: [
                                      // Waypoints: paths
                                      if (!hideWaypoints)
                                        ShapeLayer("waypointPaths",
                                            lines: log.waypoints
                                                .where((value) => value.latlng.length > 1)
                                                .map((e) => MapPolyline(points: e.latlng, width: 6.0, color: e.getColor()))
                                                .toList()),

                                      // Log line - base
                                      ShapeLayer("logBase", lines: [
                                        MapPolyline(
                                            points: log.samples.map((e) => e.latlng).toList(),
                                            width: 3,
                                            color: Colors.amber,
                                            pattern: LinePattern.dotted)
                                      ]),

                                      // --- Log Line
                                      ShapeLayer("logSelection", lines: [
                                        MapPolyline(
                                            points: log.samples
                                                .sublist(logView.sampleIndexRange.start,
                                                    min(log.samples.length, logView.sampleIndexRange.end + 1))
                                                .map((e) => e.latlng)
                                                .toList(),
                                            width: 4,
                                            borderColor: Colors.black,
                                            borderWidth: 1,
                                            color: Colors.amber)
                                      ]),
                                    ],
                                    symbols: [
                                      // Waypoint markers
                                      if (!hideWaypoints)
                                        SymbolLayer("waypoints",
                                            symbols: log.waypoints
                                                .where((e) => e.latlng.length == 1)
                                                .map((e) => waypointSymbol(e))
                                                .toList()),

                                      // --- Fuel reports
                                      SymbolLayer("fuelReports",
                                          symbols: log.fuelReportController.fuelReports.mapIndexed((index, e) {
                                            final amount = richValue(UnitType.fuel, e.amount, decimals: 1);
                                            return MapSymbol(
                                                id: "$index",
                                                alignment: Alignment.topRight,
                                                height: 40,
                                                width: 60,
                                                point: log.samples[log.timeToSampleIndex(e.time)].latlng,
                                                imageKey: "fuelReport_${amount.toPlainText()}",
                                                onTap: () {
                                                  setState(() {
                                                    selectTime(e.time.millisecondsSinceEpoch.toDouble());
                                                  });
                                                },
                                                onLongPress: () {
                                                  editFuelReport(context, index);
                                                },

                                                // Fuel Report Marker
                                                child: LabelFlag(
                                                    direction: TextDirection.ltr,
                                                    text: Text.rich(
                                                      amount,
                                                      style: const TextStyle(color: Colors.white),
                                                    ),
                                                    color: Colors.blue));
                                          }).toList()),

                                      // --- "ME" marker if selected
                                      myLocationSymbols(
                                          selectedTime.value == null
                                              ? null
                                              : log.samples[log.timeToSampleIndex(selectedTime.value!)],
                                          size: 40),
                                    ])),

                        // --- Instrument data for currently selected time
                        Align(
                          alignment: Alignment.topLeft,
                          child: DefaultTextStyle.merge(
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
                                                          //
                                                          SizedBox(
                                                            width: 60,
                                                            child: Divider(
                                                              color: Colors.grey,
                                                              height: 10,
                                                            ),
                                                          ),
                                                          // --- Elapsed Time
                                                          Text.rich(TextSpan(children: [
                                                            WidgetSpan(
                                                                child: Icon(
                                                              Icons.timer_outlined,
                                                              size: 16,
                                                              color: Colors.black,
                                                            )),
                                                            TextSpan(text: " "),
                                                            richHrMin(
                                                                duration:
                                                                    selectedTime.value!.difference(log.startTime!),
                                                                unitStyle: TextStyle(fontWeight: FontWeight.normal))
                                                          ])),
                                                          // --- Elapsed Distance
                                                          Text.rich(TextSpan(children: [
                                                            WidgetSpan(
                                                                child: Icon(
                                                              Icons.straighten,
                                                              size: 16,
                                                              color: Colors.black,
                                                            )),
                                                            TextSpan(text: " "),
                                                            richValue(
                                                                UnitType.distCoarse,
                                                                decimals: 1,
                                                                removeZeros: false,
                                                                log
                                                                    .cropLog(Range(0, log.timeToSampleIndex(time)))
                                                                    .durationDist,
                                                                unitStyle: TextStyle(fontWeight: FontWeight.normal))
                                                          ]))
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
                              padding: const EdgeInsets.all(10.0),
                              child: MapSelector(
                                size: 50,
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
                              ),
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
                    DefaultTextStyle.merge(
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
                                  <Widget>[TimeCard(time: log.startTimeOriginal, text: "Launch".tr())] +

                                      // Fuel reports
                                      log.fuelReportController
                                          .getFuelStats(log.samples)
                                          .expandIndexed<Widget>((index, e) sync* {
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
                                                                                .fuelReportController
                                                                                .fuelReports[index]
                                                                                .time
                                                                                .millisecondsSinceEpoch +
                                                                            log
                                                                                .fuelReportController
                                                                                .fuelReports[index + 1]
                                                                                .time
                                                                                .millisecondsSinceEpoch) /
                                                                        2)
                                                                    .round()),
                                                                amount: null,
                                                                validRange: log.timeRange!,
                                                                toDisplayTime: log.toOriginalTime,
                                                                fromDisplayTime: log.fromOriginalTime)
                                                            .then((newReport) {
                                                          if (newReport != null) {
                                                            setState(() {
                                                              log.fuelReportController.insertFuelReport(
                                                                  newReport.time, newReport.amount,
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
                                        if (log.fuelReportController.fuelReports.isNotEmpty)
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                            children: [
                                              FuelEntryCard(
                                                  log: log,
                                                  reportIndex: log.fuelReportController.fuelReports.length - 1,
                                                  onEdit: (reportIndex) => editFuelReport(context, reportIndex)),
                                              Container(),
                                              Container(),
                                            ],
                                          ),
                                        if (log.fuelReportController.fuelReports.length < 2)
                                          IconButton(
                                              onPressed: () => dialogEditFuelReport(
                                                          context: context,
                                                          time: log.fuelReportController.fuelReports.isEmpty
                                                              ? log.startTime!
                                                              : log.endTime!,
                                                          amount: null,
                                                          validRange: log.timeRange!,
                                                          toDisplayTime: log.toOriginalTime,
                                                          fromDisplayTime: log.fromOriginalTime)
                                                      .then((newReport) {
                                                    if (newReport != null) {
                                                      setState(() {
                                                        log.fuelReportController.insertFuelReport(
                                                            newReport.time, newReport.amount,
                                                            tolerance: const Duration(minutes: 1));
                                                      });
                                                    }
                                                  }),
                                              color: Colors.blue,
                                              visualDensity: VisualDensity.compact,
                                              icon: const Icon(Icons.add, color: Colors.white, size: 26)),
                                        // End of flight
                                        TimeCard(time: log.endTimeOriginal, text: "Landing".tr()),
                                      ]),
                        ),
                      ),
                    ),

                    // --- Engine Plot
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: showEngineTab
                            ? EngineReplay(
                                logView: logView,
                                onSelectedTime: selectTime,
                                rpmSource: hasSp140 ? "sp140" : (hasRunLeader ? "runleader" : "xc170"),
                                hasSp140: hasSp140,
                                transformController: chartTransformController,
                              )
                            : Center(child: Text("No Data".tr()))),
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
              hasSp140
                  ? Tab(icon: Icon(Icons.electric_bolt), text: "SP140")
                  : Tab(
                      icon: SizedBox(height: 24, child: SvgPicture.asset("assets/images/engine.svg")),
                      text: "gear.Engine".tr()),
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
      child: DefaultTextStyle.merge(
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
            Text(intl.DateFormat("h:mm a")
                .format(log.toOriginalTime(log.fuelReportController.fuelReports[reportIndex].time))),
            Text.rich(TextSpan(children: [
              // Icon
              WidgetSpan(child: Icon(Icons.local_gas_station, size: 18)),
              // Fuel amount
              richValue(UnitType.fuel, log.fuelReportController.fuelReports[reportIndex].amount, decimals: 1),
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
