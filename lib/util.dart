import 'dart:io';
import 'dart:math';

import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

void setSystemUI() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      // statusBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top]);
}

/// int, double, or String -> String
String? parseAsString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is int) return value.toString();
  if (value is double) return value.toString();
  if (value is bool) return value.toString();
  return null;
}

double parseAsDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.parse(value);
  return value;
}

String colorWheel(double pos) {
  // Select color from rainbow
  List<double> color = [];
  pos = pos % 1.0;
  if (pos < 1 / 3) {
    color = [pos * 3.0, (1.0 - pos * 3.0), 0.0];
  } else if (pos < 2 / 3) {
    pos -= 1 / 3;
    color = [(1.0 - pos * 3.0), 0.0, pos * 3.0];
  } else {
    pos -= 2 / 3;
    color = [0.0, pos * 3.0, (1.0 - pos * 3.0)];
  }
  color = [
    max(0, min(255, color[0] * 255)),
    max(0, min(255, color[1] * 255)),
    max(0, min(255, color[2] * 255)),
  ];
  return color[0].round().toRadixString(16).padLeft(2, "0") +
      color[1].round().toRadixString(16).padLeft(2, "0") +
      color[2].round().toRadixString(16).padLeft(2, "0");
}

/// Save string to file.
/// Returns `true` if success.
Future<bool> saveFileToAppDocs({required filename, required String data}) async {
  try {
    Directory docsDir = await getApplicationDocumentsDirectory();

    final file = File("${docsDir.path}/$filename");
    await file.create(recursive: true);
    file.writeAsString(data);
    return true;
  } catch (err, trace) {
    DatadogSdk.instance.logs?.error("Failed to save file $filename.",
        errorMessage: err.toString(), errorStackTrace: trace, attributes: {"dataLength": data.length});
    return false;
  }
}
