import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/util.dart';

class Xc170ReportScreen extends StatefulWidget {
  const Xc170ReportScreen({super.key});

  @override
  State<Xc170ReportScreen> createState() => _Xc170ReportScreenState();
}

class _Xc170ReportScreenState extends State<Xc170ReportScreen> {
  bool logLoaded = false;
  late FlightLog log;
  String? logKey;

  @override
  void didChangeDependencies() {
    if (!logLoaded) {
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, Object>;
      logKey ??= args["logKey"] as String;
      debugPrint("Loading log $logKey");

      log = logStore.logs[logKey]!;
    }
    super.didChangeDependencies();
  }

  List<TimestampDouble> getFuelData() {
    int startTime = parseAsInt(log.bleDevicesJson?["xc170"]?["datas"]?["telemetry"]?["fuel"]?["start_time"]) ?? 0;
    return log.bleDevicesJson?["xc170"]?["datas"]?["telemetry"]?["fuel"]
            ?.map((e) => TimestampDouble(e[0] + startTime, e[1]))
            .toList() ??
        [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Xc170 Report"),
      ),
      body: Column(
        children: [
          Expanded(
              child: LineChart(LineChartData(lineBarsData: [
            LineChartBarData(spots: getFuelData().map((e) => FlSpot(e.time.toDouble(), e.value)).toList())
          ])))
        ],
      ),
    );
  }
}
