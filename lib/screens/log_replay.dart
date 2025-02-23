import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:collection/collection.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

import 'package:xcnav/datadog.dart';
import 'package:xcnav/dialogs/confirm_log_crop.dart';
import 'package:xcnav/dialogs/edit_gear.dart';
import 'package:xcnav/dialogs/edit_fuel_report.dart';
import 'package:xcnav/dialogs/label_flag.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/flight_log.dart';
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

  String? logKey;
  late FlightLog log;
  bool logLoaded = false;

  late final TabController tabController;

  late final List<int> logGForceIndeces;
  final gForcePageController = PageController();

  final fuelScrollController = ScrollController();

  double mainDividerPosition = -1;

  /// Selected index range of log
  ValueNotifier<Range<int>> selectedIndexRange = ValueNotifier(Range(0, 1));
  late ValueNotifier<DateTimeRange> selectedTimeRange;

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
    scrollToTime(log.gForceEvents[index].timeRange.start.add(log.gForceEvents[index].timeRange.duration * 0.5));
    if (tabController.index != 3) {
      tabController.animateTo(3, duration: const Duration(milliseconds: 200));
      Future.delayed(const Duration(milliseconds: 220)).then((_) => gForcePageController.jumpToPage(index));
    } else {
      gForcePageController.jumpToPage(index);
    }
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
  }

  void editFuelReport(BuildContext context, int reportIndex) {
    editFuelReportDialog(context, log.fuelReports[reportIndex].time, log.fuelReports[reportIndex].amount)
        .then((newReport) {
      setState(() {
        if (newReport != null) {
          if (newReport.amount == 0 && newReport.time.millisecondsSinceEpoch == 0) {
            // Report was deleted
            log.removeFuelReport(reportIndex);
          } else {
            // Edit fuel report amount
            log.updateFuelReport(reportIndex, newReport.amount);
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("/Build log_replay screen");
    if (!logLoaded) {
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, Object>;
      logKey ??= args["logKey"] as String;

      log = logStore.logs[logKey]!;

      selectedIndexRange.value = Range(0, log.samples.length - 1);
      selectedTimeRange = ValueNotifier(DateTimeRange(start: log.startTime!, end: log.endTime!));

      if (mainDividerPosition < 0) {
        mainDividerPosition = (MediaQuery.of(context).size.height - 80) * 0.5;
      }

      if (log.goodFile) {
        logLoaded = true;
      } else {
        error("Error loading log in replay screen.", attributes: {"filename": log.filename});
      }
    }
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
                  case "trim":
                    confirmLogCrop(context,
                            trimLength: log.endTime!.difference(log.startTime!) -
                                Duration(
                                    milliseconds: log.samples[selectedIndexRange.value.end].time -
                                        log.samples[selectedIndexRange.value.end].time))
                        .then((confirmed) {
                      setState(() {
                        if (confirmed ?? false) {
                          final newLog = log.cropLog(selectedIndexRange.value);
                          logStore.updateLog(logKey!, newLog);
                          scrollToTime(log.startTime!);
                        }
                      });
                    });

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
                    value: "trim",
                    child: ListTile(
                      leading: Icon(
                        Icons.crop,
                        size: 32,
                      ),
                      title: const Text(
                        "Crop Log to Selection",
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
                              initialCameraFit: CameraFit.bounds(bounds: log.getBounds()),
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

                              // --- G-Force Events
                              ValueListenableBuilder<DateTimeRange>(
                                  valueListenable: selectedTimeRange,
                                  builder: (context, range, _) {
                                    return MarkerLayer(
                                        markers: log.gForceEvents
                                            .mapIndexed((i, e) => Marker(
                                                point: e.center.latlng,
                                                child: GestureDetector(
                                                    behavior: HitTestBehavior.opaque,
                                                    onTap: () {
                                                      gotoGForce(i);
                                                    },
                                                    child: Card(
                                                      color: Colors.black.withAlpha(
                                                          e.timeRange.start.isBefore(range.start) &&
                                                                      e.timeRange.end.isAfter(range.end) ||
                                                                  e.timeRange.start.isAfter(range.start) &&
                                                                      e.timeRange.start.isBefore(range.end) ||
                                                                  (e.timeRange.end.isAfter(range.start) &&
                                                                      e.timeRange.end.isBefore(range.end))
                                                              ? 200
                                                              : 20),
                                                      child: const Icon(
                                                        Icons.g_mobiledata,
                                                        color: Colors.lightGreen,
                                                        size: 20,
                                                      ),
                                                    ))))
                                            .toList());
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
                      padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
                      child: LogSummary(log: log),
                    ),

                    // --- Elevation Plot
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevationReplay(
                          log: log,
                          showVario: mainDividerPosition < (MediaQuery.of(context).size.height - 100) / 2,
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
                        ? const Center(child: Text("No G-force events."))
                        : GForcePages(
                            pageController: gForcePageController,
                            log: log,
                            onPageChanged: (index) {
                              scrollToTime(log.gForceEvents[index].timeRange.start
                                  .add(log.gForceEvents[index].timeRange.duration * 0.5));
                            },
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
                                          child: Scrollbar(
                                            controller: fuelScrollController,
                                            trackVisibility: true,
                                            thumbVisibility: true,
                                            child: ListView(
                                                controller: fuelScrollController,
                                                shrinkWrap: true,
                                                children: log.fuelStats.expandIndexed<Widget>((index, e) sync* {
                                                      yield Center(
                                                          child: FuelEntryCard(
                                                              log: log,
                                                              reportIndex: index,
                                                              onEdit: (reportIndex) =>
                                                                  editFuelReport(context, reportIndex)));

                                                      yield Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                                          children: [
                                                            Text("${e.durationTime.inMinutes}"),
                                                            Text(printValue(UnitType.fuel, e.rate, decimals: 1) ?? "?"),
                                                            Text(printValue(UnitType.distCoarse,
                                                                    e.mpl / unitConverters[UnitType.fuel]!(1),
                                                                    decimals: 1) ??
                                                                "?")
                                                          ]);
                                                    }).toList() +
                                                    [
                                                      Center(
                                                          child: FuelEntryCard(
                                                              log: log,
                                                              reportIndex: log.fuelReports.length - 1,
                                                              onEdit: (reportIndex) =>
                                                                  editFuelReport(context, reportIndex)))
                                                    ]),
                                          ),
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
                                    editFuelReportDialog(
                                            context,
                                            selectedTimeRange.value.start.add(selectedTimeRange.value.duration * 0.5),
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

            // --- Time Scrubber
            ValueListenableBuilder<DateTimeRange>(
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
                                  duration: valueTime.difference(valueTime == range.end ? range.start : log.startTime!))
                              .toPlainText();
                    },
                    onChanged: (newValue) {
                      final int startIndex = log.timeToSampleIndex(newValue.start);
                      final int endIndex = log.timeToSampleIndex(newValue.end);

                      selectedIndexRange.value = Range(startIndex, endIndex);
                      selectedTimeRange.value = DateTimeRange(start: newValue.start, end: newValue.end);
                    },
                  );
                }),

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

class FuelEntryCard extends StatelessWidget {
  final FlightLog log;
  final int reportIndex;
  final void Function(int index)? onEdit;

  const FuelEntryCard({super.key, required this.log, required this.reportIndex, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      color: Colors.blue,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Icon(
            Icons.local_gas_station,
            size: 18,
            // color: Colors.green,
          ),
        ),
        Text.rich(richValue(UnitType.fuel, log.fuelReports[reportIndex].amount)),
        IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () => onEdit?.call(reportIndex),
            icon: Icon(Icons.edit)),
      ]),
    );
  }
}
