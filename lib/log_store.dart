import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xcnav/datadog.dart';
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
    return logsSlice.map((e) => _logs[e]).nonNulls;
  }

  List<LogFilter>? _logFilters;
  set logFilters(List<LogFilter>? newValue) {
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

  /// The log recorded just before (or after, if [next]) this one, if the gap between them is within [maxGap].
  ///
  /// These are candidates for being the same flight split in two.
  String? findAdjacentLog(String logKey, {bool next = true, Duration maxGap = const Duration(minutes: 10)}) {
    final log = _logs[logKey];
    if (log == null || !log.goodFile) return null;
    String? bestKey;
    int? bestGap;
    for (final entry in _logs.entries) {
      final other = entry.value;
      if (entry.key == logKey || !other.goodFile) continue;
      final gap = next
          ? other.startTime!.difference(log.endTime!).inMilliseconds
          : log.startTime!.difference(other.endTime!).inMilliseconds;
      // Overlapping logs can't be the same flight
      if (gap <= 0 || gap > maxGap.inMilliseconds) continue;
      if (bestGap == null || gap < bestGap) {
        bestGap = gap;
        bestKey = entry.key;
      }
    }
    return bestKey;
  }

  /// Merge two logs into one. The earlier log's file is kept and the later log's file is deleted.
  ///
  /// Returns the key of the merged log.
  Future<String> mergeLogs(String keyA, String keyB) async {
    final a = _logs[keyA]!;
    final b = _logs[keyB]!;
    final aFirst = !b.startTime!.isBefore(a.startTime!);
    final keepKey = aFirst ? keyA : keyB;
    final dropKey = aFirst ? keyB : keyA;

    final merged = FlightLog.merge(a, b);
    // Make sure the merged log is written before removing anything
    await merged.save();
    if (merged.filename != keepKey) {
      _logs.remove(keepKey);
    }
    deleteLog(dropKey);
    return merged.filename!;
  }

  /// Load only the most recently started log from disk. (Doesn't require the whole store to be loaded.)
  Future<FlightLog?> loadMostRecentLog() async {
    final Directory dir = Directory("${(await getApplicationDocumentsDirectory()).path}/flight_logs/");
    if (!await dir.exists()) return null;

    // Logs are named by their start time in ms
    File? latest;
    int latestTime = 0;
    await for (final each in dir.list(recursive: false, followLinks: false)) {
      if (each is! File) continue;
      final time = int.tryParse(each.uri.pathSegments.last.split(".").first);
      if (time != null && time > latestTime) {
        latestTime = time;
        latest = each;
      }
    }
    if (latest == null) return null;

    try {
      final raw = await latest.readAsString();
      final log = FlightLog.fromJson(latest.path, jsonDecode(raw), rawJson: raw);
      return log.goodFile ? log : null;
    } catch (err, trace) {
      error("Failed to load most recent FlightLog",
          errorMessage: err.toString(), errorStackTrace: trace, attributes: {"filename": latest.path});
      return null;
    }
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
            error("Failed to load FlightLog",
                errorMessage: err.toString(), errorStackTrace: trace, attributes: {"filename": each.uri});
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
