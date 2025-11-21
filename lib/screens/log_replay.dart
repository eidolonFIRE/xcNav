import 'dart:math';
import 'package:easy_localization/easy_localization.dart' as tr;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart' as intl;
import 'package:syncfusion_flutter_sliders/sliders.dart';

import 'package:xcnav/datadog.dart';
import 'package:xcnav/dialogs/confirm_log_crop.dart';
import 'package:xcnav/dialogs/edit_gear.dart';
import 'package:xcnav/dialogs/edit_fuel_report.dart';
import 'package:xcnav/dialogs/label_flag.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/elevation_replay.dart';
import 'package:xcnav/widgets/g_force_pages.dart';
import 'package:xcnav/widgets/log_summary.dart';
import 'package:xcnav/widgets/map_selector.dart';
import 'package:xcnav/widgets/replay_tab.dart';
import 'package:xcnav/widgets/speed_histogram.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

class LogReplay extends StatefulWidget {
  const LogReplay({super.key});

  @override
  State<LogReplay> createState() => _LogReplayState();
}

class _LogReplayState extends State<LogReplay> with SingleTickerProviderStateMixin {
  static const int _replayTabIndex = 1;
  final mapKey = GlobalKey(debugLabel: "replayMap");
  final mapController = MapController();
  bool mapReady = false;
  MapTileSrc mapTileSrc = MapTileSrc.topo;
  bool hideWaypoints = false;
  double mapOpacity = 1.0;
  ValueNotifier<bool> isMapDialOpen = ValueNotifier(false);

  String? logKey;
  late FlightLog log;
  bool logLoaded = false;

  double windowHeight = 400;
  double bottomViewPadding = 0;

  late final TabController tabController;

  late final List<int> logGForceIndeces;
  final gForcePageController = PageController();

  final fuelScrollController = ScrollController();

  double mainDividerPosition = -1;

  /// Selected index range of log
  ValueNotifier<Range<int>> selectedIndexRange = ValueNotifier(Range(0, 1));
  late ValueNotifier<DateTimeRange> selectedTimeRange;
  ValueNotifier<int> replaySampleIndex = ValueNotifier(0);
  List<double> cumulativeReplayDistances = [];

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 6, vsync: this);
    tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (!tabController.indexIsChanging &&
          tabController.index == _replayTabIndex) {
        _focusReplayOnCurrentRange();
      }
    });
  }

  @override
  void didChangeDependencies() {
    if (!logLoaded) {
      debugPrint("Loading log $logKey");
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, Object>;
      logKey ??= args["logKey"] as String;

      log = logStore.logs[logKey]!;

      selectedIndexRange.value = Range(0, log.samples.length - 1);
      selectedTimeRange = ValueNotifier(DateTimeRange(start: log.startTime!, end: log.endTime!));

      if (log.goodFile) {
        logLoaded = true;
        _initializeReplayData();
      } else {
        error("Error loading log in replay screen.", attributes: {"filename": log.filename});
      }
    }
    final mediaQuery = MediaQuery.of(context);
    bottomViewPadding = mediaQuery.viewPadding.bottom;
    windowHeight = mediaQuery.size.height - bottomViewPadding;
    if (windowHeight <= 0) {
      windowHeight = mediaQuery.size.height;
    }
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

  void gotoGForce(int index) {
    scrollToTimeRange(log.gForceEvents[index].timeRange);
    if (tabController.index != 4) {
      tabController.animateTo(4, duration: const Duration(milliseconds: 200));
      Future.delayed(const Duration(milliseconds: 220)).then((_) => gForcePageController.jumpToPage(index));
    } else {
      gForcePageController.jumpToPage(index);
    }
  }

  void scrollToTimeRange(DateTimeRange range) {
    final startIndex = log.timeToSampleIndex(range.start);
    final endIndex = log.timeToSampleIndex(range.end);
    selectedTimeRange.value = DateTimeRange(
        start: DateTime.fromMillisecondsSinceEpoch(log.samples[startIndex].time),
        end: DateTime.fromMillisecondsSinceEpoch(log.samples[endIndex].time));
    selectedIndexRange.value = Range(startIndex, endIndex);
    fitMap();
  }

  void scrollToTime(DateTime center) {
    mapController.move(log.samples[log.timeToSampleIndex(center)].latlng, mapController.camera.zoom);
    final durWidth = selectedTimeRange.value.duration;
    final startIndex = log.timeToSampleIndex(center.subtract(durWidth * 0.5));
    final endIndex = log.timeToSampleIndex(center.add(durWidth * 0.5));
    selectedTimeRange.value = DateTimeRange(
        start: DateTime.fromMillisecondsSinceEpoch(log.samples[startIndex].time),
        end: DateTime.fromMillisecondsSinceEpoch(log.samples[endIndex].time));
    selectedIndexRange.value = Range(startIndex, endIndex);
    fitMap();
    _updateReplayTime(center);
  }

  void fitMap() {
    mapController.fitCamera(CameraFit.coordinates(
        coordinates: log.samples
            .sublist(selectedIndexRange.value.start, selectedIndexRange.value.end)
            .map((e) => e.latlng)
            .toList(),
        padding: EdgeInsets.all(50),
        minZoom: 4,
        maxZoom: 14));
  }

  void _initializeReplayData() {
    if (log.samples.isEmpty || cumulativeReplayDistances.isNotEmpty) {
      return;
    }

    cumulativeReplayDistances =
        List<double>.filled(log.samples.length, 0, growable: false);
    double runningDistance = 0;
    for (int i = 1; i < log.samples.length; i++) {
      runningDistance += log.samples[i - 1].distanceTo(log.samples[i]);
      cumulativeReplayDistances[i] = runningDistance;
    }
    replaySampleIndex.value = 0;
  }

  void _setReplayIndex(int index, {bool followMap = false}) {
    if (log.samples.isEmpty) return;
    final clampedIndex = max(0, min(index, log.samples.length - 1));
    if (replaySampleIndex.value == clampedIndex) return;
    replaySampleIndex.value = clampedIndex;
    if (followMap && mapReady) {
      mapController.move(
          log.samples[clampedIndex].latlng, mapController.camera.zoom);
    }
  }

  void _updateReplayTime(DateTime time, {bool followMap = false}) {
    _setReplayIndex(log.timeToSampleIndex(time), followMap: followMap);
  }

  double _replayDistanceForIndex(int index) {
    if (cumulativeReplayDistances.isEmpty) {
      return 0;
    }
    final clampedIndex =
        max(0, min(index, cumulativeReplayDistances.length - 1));
    return cumulativeReplayDistances[clampedIndex];
  }

  void _focusReplayOnCurrentRange() {
    if (!logLoaded || log.samples.isEmpty) return;
    final range = selectedIndexRange.value;
    final centerIndex = (range.start + range.end) ~/ 2;
    _setReplayIndex(centerIndex, followMap: true);
  }

  Widget _buildRangeSlider() {
    return ValueListenableBuilder<DateTimeRange>(
        key: const ValueKey("range_slider"),
        valueListenable: selectedTimeRange,
        builder: (context, range, _) {
          return SfRangeSlider(
            values: SfRangeValues(range.start, range.end),
            dragMode: SliderDragMode.both,
            min: log.startTime,
            max: log.endTime,
            enableTooltip: true,
            tooltipTextFormatterCallback: (value, formattedText) {
              DateTime valueTime = value;
              return (valueTime == range.end ? "+" : "") +
                  richHrMin(
                          duration: valueTime.difference(valueTime == range.end
                              ? range.start
                              : log.startTime!))
                      .toPlainText();
            },
            onChanged: (newValue) {
              scrollToTimeRange(
                  DateTimeRange(start: newValue.start, end: newValue.end));
            },
          );
        });
  }

  Widget _buildReplaySlider() {
    return ValueListenableBuilder<int>(
        key: const ValueKey("replay_slider"),
        valueListenable: replaySampleIndex,
        builder: (context, index, _) {
          if (log.samples.isEmpty) {
            return const SizedBox.shrink();
          }
          final safeIndex = max(0, min(index, log.samples.length - 1));
          final DateTime replayTime =
              DateTime.fromMillisecondsSinceEpoch(log.samples[safeIndex].time);
          return SfSlider(
            value: replayTime,
            min: log.startTime,
            max: log.endTime,
            enableTooltip: true,
            tooltipTextFormatterCallback: (value, formattedText) {
              final DateTime valueTime = value;
              return richHrMin(
                      duration: valueTime.difference(log.startTime!),
                      longUnits: false)
                  .toPlainText();
            },
            onChanged: (dynamic newValue) {
              if (newValue is DateTime) {
                _updateReplayTime(newValue, followMap: true);
              }
            },
          );
        });
  }

  Widget _buildTimeScrubber() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: tabController.index == _replayTabIndex
          ? _buildReplaySlider()
          : _buildRangeSlider(),
    );
  }

  Widget _buildReplayTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ValueListenableBuilder<int>(
          valueListenable: replaySampleIndex,
          builder: (context, sampleIndex, _) {
            if (log.samples.isEmpty) {
              return const Center(child: Text("Replay data unavailable"));
            }
            final safeIndex = max(0, min(sampleIndex, log.samples.length - 1));
            final sample = log.samples[safeIndex];
            final Duration elapsed =
                Duration(milliseconds: sample.time - log.samples.first.time);
            final double distance = _replayDistanceForIndex(safeIndex);
            const valueStyle = TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white);
            const unitStyle = TextStyle(fontSize: 12, color: Colors.grey);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Replay".tr(),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    ReplayStatusField(
                        label: "Time".tr(),
                        child: Text.rich(richHrMin(
                            duration: elapsed,
                            valueStyle: valueStyle,
                            unitStyle: unitStyle))),
                    ReplayStatusField(
                        label: "Altitude".tr(),
                        child: Text.rich(richValue(
                            UnitType.distFine, sample.alt,
                            decimals: 0,
                            valueStyle: valueStyle,
                            unitStyle: unitStyle))),
                    ReplayStatusField(
                        label: "Speed".tr(),
                        child: Text.rich(richValue(UnitType.speed, sample.spd,
                            decimals: 1,
                            valueStyle: valueStyle,
                            unitStyle: unitStyle))),
                    ReplayStatusField(
                        label: "Distance".tr(),
                        child: Text.rich(richValue(
                            UnitType.distCoarse, distance,
                            decimals: 1,
                            valueStyle: valueStyle,
                            unitStyle: unitStyle))),
                  ],
                ),
              ],
            );
          }),
    );
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
                    if (selectedIndexRange.value.start <= 2 && selectedIndexRange.value.end >= log.samples.length - 3) {
                      showCropCutSuggestion(context);
                    } else {
                      confirmLogCrop(context,
                              trimStart: Duration(
                                  milliseconds:
                                      log.samples[selectedIndexRange.value.start].time - log.samples.first.time),
                              trimEnd: Duration(
                                  milliseconds:
                                      -log.samples[selectedIndexRange.value.end].time + log.samples.last.time))
                          .then((confirmed) {
                        setState(() {
                          if (confirmed ?? false) {
                            final newLog = log.cropLog(selectedIndexRange.value);
                            logStore.updateLog(logKey!, newLog);
                            log = newLog;
                            scrollToTimeRange(DateTimeRange(start: newLog.startTime!, end: newLog.endTime!));
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
        body: SafeArea(top: false, maintainBottomViewPadding: true, child: Column(
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

                              if (tabController.index != _replayTabIndex)
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

                              if (tabController.index == _replayTabIndex)
                                ValueListenableBuilder<int>(
                                    valueListenable: replaySampleIndex,
                                    builder: (context, replayIndex, _) {
                                      if (log.samples.length < 2) {
                                        return PolylineLayer(
                                            polylines: const <Polyline>[]);
                                      }
                                      final safeIndex = max(0, min(replayIndex, log.samples.length - 1));
                                      final beforePoints = log.samples.take(safeIndex + 1).map((e) => e.latlng).toList();
                                      final afterPoints = log.samples.sublist(safeIndex).map((e) => e.latlng).toList();
                                      return PolylineLayer(polylines: [
                                        if (afterPoints.length > 1)
                                          Polyline(
                                              points: afterPoints,
                                              strokeWidth: 3,
                                              borderColor: Colors.black,
                                              color: Colors.amber,
                                              pattern:
                                                  StrokePattern.dotted()),
                                        if (beforePoints.length > 1)
                                          Polyline(
                                              points: beforePoints,
                                              strokeWidth: 4,
                                              borderColor: Colors.black,
                                              borderStrokeWidth: 1,
                                              color: Colors.amber),
                                      ]);
                                    }),

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
                              if (tabController.index != _replayTabIndex)
                                ValueListenableBuilder<Range>(
                                    valueListenable: selectedIndexRange,
                                    builder: (context, range, _) {
                                      return PolylineLayer(polylines: [
                                        Polyline(
                                            points:
                                                log.samples.sublist(range.start, range.end).map((e) => e.latlng).toList(),
                                            strokeWidth: 4,
                                            borderColor: Colors.black,
                                            borderStrokeWidth: 1,
                                            color: Colors.amber
                                            // gradientColors: [Colors.amber, Colors.orange],
                                            )
                                      ]);
                                    }),

                              if (tabController.index == _replayTabIndex)
                                ValueListenableBuilder<int>(
                                    valueListenable: replaySampleIndex,
                                    builder: (context, replayIndex, _) {
                                      if (log.samples.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      final safeIndex = max(0, min(replayIndex, log.samples.length - 1));
                                      final sample = log.samples[safeIndex];
                                      const double arrowSize = 20;
                                      return MarkerLayer(markers: [
                                        Marker(
                                            alignment: Alignment.center,
                                            point: sample.latlng,
                                            width: arrowSize,
                                            height: arrowSize,
                                            rotate: true,
                                            child: Transform.rotate(
                                                angle: sample.hdg,
                                                child: const ReplayMapArrow(size: arrowSize)))
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
                                                scrollToTime(e.time);
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
                      child: ValueListenableBuilder<Range<int>>(
                          valueListenable: selectedIndexRange,
                          builder: (context, range, _) {
                            return LogSummary(log: log.cropLog(range));
                          }),
                    ),

                    // --- Replay
                    _buildReplayTab(),

                    // --- Elevation Plot
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevationReplay(
                          log: log,
                          showVario: true,
                          selectedIndexRange: selectedIndexRange,
                          onSelectedGForce: gotoGForce,
                        )),

                    // --- Speed Histogram
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SpeedHistogram(
                          log: log,
                          selectedIndexRange: selectedIndexRange,
                        )),

                    // --- G-force event pages
                    (log.gForceEvents.isEmpty)
                        ? Center(child: Text("empty_list".tr()))
                        : GForcePages(
                            pageController: gForcePageController,
                            log: log,
                            onPageChanged: (index) {
                              scrollToTimeRange(log.gForceEvents[index].timeRange);
                            },
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

            // --- Time Scrubber
            _buildTimeScrubber(),

            TabBar(labelPadding: EdgeInsets.zero, controller: tabController, tabs: [
              Tab(icon: Icon(Icons.info), text: "Summary".tr()),
              Tab(icon: const ReplayTabIcon(), text: "Replay".tr()),
              Tab(
                icon: Icon(Icons.area_chart),
                text: "Altitude".tr(),
              ),
              Tab(icon: Icon(Icons.speed), text: "Speed".tr()),
              Tab(icon: Icon(Icons.g_mobiledata), text: "G-Force".tr()),
              Tab(icon: Icon(Icons.local_gas_station), text: "Fuel".tr()),
            ]),
          ],
        ),),
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
