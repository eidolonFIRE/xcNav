import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// Models
import 'package:xcnav/models/flight_log.dart';

// Widgets
import 'package:xcnav/widgets/flight_log_summary.dart';

class FlightLogViewer extends StatefulWidget {
  const FlightLogViewer({Key? key}) : super(key: key);

  @override
  State<FlightLogViewer> createState() => _FlightLogViewerState();
}

class _FlightLogViewerState extends State<FlightLogViewer> {
  Map<String, FlightLog> logs = {};

  @override
  void initState() {
    super.initState();
    refreshLogsFromDirectory();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void refreshLogsFromDirectory() async {
    final Directory _appDocDir = await getApplicationDocumentsDirectory();
    final Directory _appDocDirFolder =
        Directory("${_appDocDir.path}/flight_logs/");
    if (await _appDocDirFolder.exists()) {
      //if folder already exists return path
      logs.clear();
      // Async load in all the files
      _appDocDirFolder
          .list(recursive: false, followLinks: false)
          .forEach((each) {
        File.fromUri(each.uri).readAsString().then((value) {
          setState(() {
            logs[each.uri.path] =
                FlightLog.fromJson(each.path, jsonDecode(value));
          });
        });
      });
      // setState(() {});
    } else {
      debugPrint('"flight_logs" directory doesn\'t exist yet!');
    }
  }

  @override
  Widget build(BuildContext context) {
    var keys = logs.keys.toList();
    keys.sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Flight Logs",
        ),
        // centerTitle: true,
        // TODO: show some aggregate numbers here
      ),
      body: ListView(
        children: keys
            .map((e) => FlightLogSummary(logs[e]!, refreshLogsFromDirectory))
            .toList(),
      ),
    );
  }
}
