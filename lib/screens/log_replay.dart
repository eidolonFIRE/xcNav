import 'dart:math';
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

  double windowHeight = 400;

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

  void infoSetTrimTime(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => const AlertDialog(
              content: Text("Use the slider to select the trim position."),
            ));
  }

  void gotoGForce(int index) {
    scrollToTimeRange(log.gForceEvents[index].timeRange);
    if (tabController.index != 3) {
      tabController.animateTo(3, duration: const Duration(milliseconds: 200));
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
                title: Text("Invalid Selection"),
                content: Text("Use the range slider to select the duration of the log to keep."),
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
                const PopupMenuItem(
                  value: "edit_gear",
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text("Edit Gear"),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                    value: "crop",
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
                        ? const Center(child: Text("No G-force events."))
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
                                  <Widget>[TimeCard(time: log.startTime, text: "Launch")] +

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
                                        TimeCard(time: log.endTime, text: "Landing"),
                                      ]),
                        ),
                      ),
                    ),
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
                      scrollToTimeRange(DateTimeRange(start: newValue.start, end: newValue.end));
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
