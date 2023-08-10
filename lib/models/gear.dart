import 'package:flutter/material.dart';
import 'package:xcnav/util.dart';

class Gear {
  String? wingMakeModel;

  /// Can be int or str.
  /// example: 20, XS
  String? wingSize;
  Color? wingColor;

  String? frameMakeModel;
  String? engine;
  String? prop;

  /// Liters
  double? tankSize;
  double? bladderSize;

  String? other;

  Gear();

  Gear.fromJson(Map<String, dynamic> data) {
    wingMakeModel = data["wing_make_model"];
    wingSize = parseAsString(data["wing_size"]);
    wingColor = data["wing_color"] != null ? Color(data["wing_color"]) : null;
    frameMakeModel = data["motor_make_model"];
    engine = parseAsString(data["engine"]);
    prop = parseAsString(data["prop"]);
    tankSize = parseAsDouble(data["tank_size"]);
    bladderSize = parseAsDouble(data["blader_size"]);
    other = data["other"];
  }

  Map<String, dynamic> toJson() {
    final dict = {
      "wing_make_model": wingMakeModel,
      "wing_size": wingSize,
      "wing_color": wingColor?.value,
      "frame_make_model": frameMakeModel,
      "engine": engine,
      "prop": prop,
      "tank_size": tankSize?.toStringAsFixed(2),
      "blader_size": bladderSize?.toStringAsFixed(2),
      "other": other,
    };
    return dict;
  }
}
