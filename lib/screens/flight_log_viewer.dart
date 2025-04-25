import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xcnav/dialogs/edit_log_filters.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/models/flight_log.dart';

// Models
import 'package:xcnav/widgets/basic_log_aggregate.dart';
import 'package:xcnav/widgets/chart_log_aggregate.dart';
import 'package:xcnav/widgets/chart_log_duration_hist.dart';
import 'package:xcnav/widgets/chart_log_fuel_insights.dart';

// Widgets
import 'package:xcnav/widgets/flight_log_card.dart';

class FlightLogViewer extends StatefulWidget {
  const FlightLogViewer({super.key});

  @override
  State<FlightLogViewer> createState() => _FlightLogViewerState();
}

class _FlightLogViewerState extends State<FlightLogViewer> with TickerProviderStateMixin {
  late final TabController mainTabController;
  final logListController = ScrollController();

  // Fuel Chart
  ChartFuelModeX chartFuelX = ChartFuelModeX.spd;
  ChartFuelModeY chartFuelY = ChartFuelModeY.rate;

  @override
  void initState() {
    super.initState();
    mainTabController = TabController(length: 2, vsync: this);

    // --- Generate fake logs for debugging
    // final rand = Random();
    // for (int t = 0; t < 50; t++) {
    //   debugPrint("Gen fake log: $t");
    //   final startTime = DateTime.now().subtract(Duration(days: rand.nextInt(600), hours: rand.nextInt(24)));
    //   logs["$t"] = FlightLog.fromJson("$t", {
    //     "samples": [
    //       Geo.fromJson({
    //         "lat": 1,
    //         "lng": 1,
    //         "alt": 1,
    //         "time": startTime.millisecondsSinceEpoch,
    //         "hdg": 0,
    //         "spd": 0,
    //         "vario": 0
    //       }).toJson(),
    //       Geo.fromJson({
    //         "lat": 1,
    //         "lng": 2,
    //         "alt": 1,
    //         "time": startTime
    //             .add(Duration(minutes: (60 + pow(rand.nextDouble(), 1.2) * (rand.nextInt(2) * 2 - 1) * 50).round()))
    //             .millisecondsSinceEpoch,
    //         "hdg": 0,
    //         "spd": 0,
    //         "vario": 0
    //       }).toJson()
    //     ]
    //   });
    // }

    // loaded = true;
    // refreshSlice(sliceSize);
  }

  @override
  void dispose() {
    super.dispose();
    mainTabController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("Build /flightLogs");
    if (logStore.loaded.value != true) {
      logStore.refreshLogsFromDirectory().then((value) {
        setState(() {
          debugPrint("Refreshed flight logs");
        });
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Flight Logs",
        ),
        actions: [
          PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case "import":
                    final defaultDir = await getDownloadsDirectory();

                    final results = await FilePicker.platform
                        .pickFiles(initialDirectory: defaultDir?.path, allowMultiple: true, type: FileType.any);
                    if (results != null) {
                      for (final file in results.files) {
                        if (file.name.toLowerCase().endsWith("igc")) {
                          final rawStr = await file.xFile.readAsString();
                          final newLog = FlightLog.fromIGC(rawStr);
                          await newLog.save();
                        }
                      }
                      logStore.refreshLogsFromDirectory();
                    }
                    break;
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem(
                      value: "import",
                      child: ListTile(
                        leading: Icon(Icons.file_open),
                        title: Text("Import IGC"),
                      ),
                    ),
                  ])
        ],
        bottom: TabBar(controller: mainTabController, tabs: const [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(12.0),
                child: Icon(Icons.list),
              ),
              Text("Entries")
            ],
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: EdgeInsets.all(12.0),
              child: Icon(Icons.insights),
            ),
            Text("Stats")
          ]),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          editLogFilters(context).then((value) {
            if (value != null) {
              logStore.logFilters = value;
            }
          });
        },
        child: const Icon(Icons.search),
      ),
      body: AnimatedBuilder(
          animation: logStore,
          builder: (context, _) {
            debugPrint("Build /flightLogs - animatedBuilder");
            return TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              controller: mainTabController,
              children: [
                // --- Each
                !logStore.loaded.value
                    ? const Center(
                        child: CircularProgressIndicator.adaptive(),
                      )
                    : (logStore.logs.isEmpty
                        ? const Center(child: Text("Wow, such empty!"))
                        : ListView(
                            controller: logListController,
                            children: logStore.logsSlice.reversed.map((e) => FlightLogCard(e)).toList(),
                          )),

                // --- Stats
                !logStore.loaded.value
                    ? const Center(
                        child: CircularProgressIndicator.adaptive(),
                      )
                    : ListView(
                        children: [
                          Container(
                            height: 10,
                          ),

                          // --- Basic Aggregate
                          Text(
                            "Summary",
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Card(
                              color: Colors.grey.shade800,
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: BasicLogAggregate(logs: logStore.logsSliceLogs),
                              ),
                            ),
                          ),

                          Container(
                            height: 10,
                          ),

                          // --- Hist
                          Text(
                            "Flight Duration (histogram)",
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          SizedBox(
                            height: 200,
                            child: ClipRect(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 20, top: 4),
                                child: Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: ChartLogDurationHist(
                                    logs: logStore.logsSliceLogs,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Container(
                            height: 10,
                          ),

                          // --- Monthly Aggregate
                          // if (sliceSize.index > SliceSize.month.index)
                          Text(
                            "Monthly Totals",
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          // if (sliceSize.index > SliceSize.month.index)
                          SizedBox(
                            height: 200,
                            child: Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: ChartLogAggregate(
                                logs: logStore.logsSliceLogs,
                                mode: ChartLogAggregateMode.year,
                              ),
                            ),
                          ),

                          Container(
                            height: 10,
                          ),
                          Text(
                            "Fuel Insights",
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),

                          Container(
                            height: 10,
                          ),

                          SizedBox(
                            height: 200,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 0, 20, 10),
                              child: ChartLogFuelInsights(
                                logsSlice: logStore.logsSliceLogs,
                                chartFuelModeX: chartFuelX,
                                chartFuelModeY: chartFuelY,
                              ),
                            ),
                          ),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ToggleButtons(
                                isSelected: ChartFuelModeY.values.map((e) => e == chartFuelY).toList(),
                                onPressed: (index) {
                                  setState(() {
                                    chartFuelY = ChartFuelModeY.values[index];
                                  });
                                },
                                children: const [
                                  Text(
                                    "Burn\nRate",
                                    textAlign: TextAlign.center,
                                  ),
                                  Text("Eff.")
                                ],
                              ),
                              SizedBox(
                                  width: 40,
                                  child: const Divider(
                                    thickness: 2,
                                  )),
                              ToggleButtons(
                                isSelected: ChartFuelModeX.values.map((e) => e == chartFuelX).toList(),
                                onPressed: (index) {
                                  setState(() {
                                    chartFuelX = ChartFuelModeX.values[index];
                                  });
                                },
                                children: const [
                                  Text("Alt."),
                                  Text(
                                    "Alt.\nGained",
                                    textAlign: TextAlign.center,
                                  ),
                                  Text("Speed")
                                ],
                              )
                            ],
                          ),

                          Container(
                            height: 100,
                          ),
                        ],
                      )
              ],
            );
          }),
    );
  }
}
