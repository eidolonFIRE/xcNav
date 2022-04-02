import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

// Providers
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/chat.dart';
import 'package:xcnav/providers/profile.dart';

// Models
import 'package:xcnav/models/message.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/models/flightLog.dart';

// Widgets
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/chat_bubble.dart';
import 'package:xcnav/widgets/flight_log_entry.dart';

class FlightLogViewer extends StatefulWidget {
  const FlightLogViewer({Key? key}) : super(key: key);

  @override
  State<FlightLogViewer> createState() => _FlightLogViewerState();
}

class _FlightLogViewerState extends State<FlightLogViewer> {
  List<FlightLog> logs = [];

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
      // TODO: ensure some sorted order (atm it's race)
      _appDocDirFolder
          .list(recursive: false, followLinks: false)
          .forEach((each) {
        File.fromUri(each.uri).readAsString().then((value) {
          logs.add(FlightLog.fromJson(each.path, jsonDecode(value)));
          setState(() {});
        });
      });
      setState(() {});
    } else {
      debugPrint('"flight_logs" directory doesn\'t exist yet!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Flights",
        ),
        centerTitle: true,
        // TODO: show some aggregate numbers here
      ),
      body: ListView(
        children: logs
            .map((e) => FlightLogEntry(e, refreshLogsFromDirectory))
            .toList(),
      ),
    );
  }
}
