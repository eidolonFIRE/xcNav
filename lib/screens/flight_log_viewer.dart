import 'dart:async';
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
  bool loaded = false;

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
    final Directory _appDocDirFolder = Directory("${_appDocDir.path}/flight_logs/");
    if (await _appDocDirFolder.exists()) {
      //if folder already exists return path
      setState(() {
        loaded = false;
      });

      logs.clear();

      // Async load in all the files
      var files = await _appDocDirFolder.list(recursive: false, followLinks: false).toList();
      // debugPrint("${files.length} log files found.");
      List<Completer> completers = [];
      for (var each in files) {
        var _completer = Completer();
        completers.add(_completer);
        File.fromUri(each.uri).readAsString().then((value) {
          try {
            logs[each.uri.path] = FlightLog.fromJson(each.path, jsonDecode(value));
          } catch (e) {
            debugPrint(e.toString());
            if (logs[each.uri.path] != null) {
              logs[each.uri.path]!.goodFile = false;
            } else {
              debugPrint("Failed to load log: ${each.uri.path}");
            }
          }
          _completer.complete();
        });
      }
      // debugPrint("${completers.length} completers created.");
      Future.wait(completers.map((e) => e.future).toList()).then((value) {
        setState(() {
          loaded = true;
        });
      });
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
        title: Text(
          "Flight Logs  (${keys.length})",
        ),
        // TODO: show some aggregate numbers here
      ),
      body: !loaded
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView.builder(
              itemCount: keys.length,
              itemBuilder: (context, index) => FlightLogSummary(logs[keys[index]]!, refreshLogsFromDirectory),
            ),
    );
  }
}
