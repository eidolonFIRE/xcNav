import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xcnav/dialogs/edit_log_filters.dart';
import 'package:xcnav/models/flight_log.dart';

final logStore = LogStore();

class LogStore with ChangeNotifier {
  final Map<String, FlightLog> _logs = {};
  Map<String, FlightLog> get logs => _logs;

  List<String>? _logsSlice;
  List<String> get logsSlice {
    _logsSlice ??= _refreshSlice();
    return _logsSlice!;
  }

  Iterable<FlightLog> get logsSliceLogs {
    return logsSlice.map((e) => _logs[e]!);
  }

  List<LogFilter>? _logFilters;
  set logFilters(newValue) {
    _logsSlice = null;
    _logFilters = newValue;
    notifyListeners();
  }

  ValueNotifier<bool> loaded = ValueNotifier(false);

  /// Permanently delete a log.
  void deleteLog(String logKey) {
    debugPrint("Delete log: $logKey, ${logs[logKey]?.title}");
    if (logs[logKey]!.filename != null) {
      File logFile = File(logs[logKey]!.filename!);
      logFile.exists().then((value) {
        logFile.deleteSync();
      });
    }
    logs.remove(logKey);
    _logsSlice = null;
    notifyListeners();
  }

  ///
  void updateLog(String logKey, FlightLog log) {
    debugPrint("Update log: $logKey, ${log.title}");
    _logs[logKey] = log;
    _logsSlice = null;
    notifyListeners();
  }

  ///
  Future refreshLogsFromDirectory() async {
    _logs.clear();
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory appDocDirFolder = Directory("${appDocDir.path}/flight_logs/");
    if (await appDocDirFolder.exists()) {
      loaded.value = false;

      // Async load in all the files
      var files = await appDocDirFolder.list(recursive: false, followLinks: false).toList();
      // debugPrint("${files.length} log files found.");
      List<Completer> completers = [];
      for (var each in files) {
        var completer = Completer();
        completers.add(completer);

        File.fromUri(each.uri).readAsString().then((value) {
          debugPrint("Loading log: ${each.uri.path}");
          try {
            _logs[each.uri.path] = FlightLog.fromJson(each.path, jsonDecode(value), rawJson: value);
            // completer.complete();
          } catch (err, trace) {
            // This is reached if the error happens during json parsing
            // Create a "bad file" entry so user can opt to remove it
            _logs[each.uri.path] = FlightLog.fromJson(each.path, {}, rawJson: value);
            debugPrint("Caught log loading error on file ${each.uri}: $err $trace");
            DatadogSdk.instance.logs?.error("Failed to load FlightLog",
                errorMessage: err.toString(), errorStackTrace: trace, attributes: {"filename": each.path});
          }
          completer.complete();
        });
      }
      // debugPrint("${completers.length} completers created.");
      return Future.wait(completers.map((e) => e.future).toList()).then((value) {
        _logsSlice = null;
        loaded.value = true;
      });
    } else {
      debugPrint('"flight_logs" directory doesn\'t exist yet!');
      loaded.value = true;
      return Future.value();
    }
  }

  List<String> _refreshSlice() {
    debugPrint("Refresh log slice");
    late List<String> slice;
    if (_logFilters?.isNotEmpty ?? false) {
      // Filter logs by search functions
      slice = _logs.keys.where((key) => _logFilters!.map((e) => e(_logs[key]!)).reduce((a, b) => a && b)).toList();
    } else {
      slice = _logs.keys.toList();
    }
    slice.sort((a, b) =>
        (_logs[a]!.startTime?.millisecondsSinceEpoch ?? 0) - (_logs[b]!.startTime?.millisecondsSinceEpoch ?? 0));
    return slice;
  }
}
