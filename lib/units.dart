import 'dart:math';
import 'package:flutter/material.dart';

// --- Constant unit converters
const km2Miles = 0.621371;
const meters2Feet = 3.28084;
const meters2Miles = km2Miles / 1000;

enum UnitType {
  speed,
  vario,
  distFine,
  distCoarse,
  fuel,
}

enum DisplayUnitsSpeed {
  mph,
  kts,
  kph,
  mps,
}

enum DisplayUnitsVario {
  fpm,
  mps,
}

enum DisplayUnitsDist {
  imperial,
  metric,
}

enum DisplayUnitsFuel {
  liter,
  gal,
}

const Map<bool, Map<UnitType, dynamic>> _unitStr = {
  false: {
    UnitType.speed: {
      DisplayUnitsSpeed.mph: "mph",
      DisplayUnitsSpeed.kts: "kts",
      DisplayUnitsSpeed.kph: "kph",
      DisplayUnitsSpeed.mps: "m/s",
    },
    UnitType.vario: {
      DisplayUnitsVario.fpm: "ft/m",
      DisplayUnitsVario.mps: "m/s",
    },
    UnitType.distFine: {
      DisplayUnitsDist.imperial: "ft",
      DisplayUnitsDist.metric: "m",
    },
    UnitType.distCoarse: {
      DisplayUnitsDist.imperial: "mi",
      DisplayUnitsDist.metric: "km",
    },
    UnitType.fuel: {
      DisplayUnitsFuel.liter: "L",
      DisplayUnitsFuel.gal: "gal",
    }
  },
  true: {
    UnitType.speed: {
      DisplayUnitsSpeed.mph: "miles per hour",
      DisplayUnitsSpeed.kts: "knots",
      DisplayUnitsSpeed.kph: "kilometers per hour",
      DisplayUnitsSpeed.mps: "meters per second",
    },
    UnitType.vario: {
      DisplayUnitsVario.fpm: "feet per minute",
      DisplayUnitsVario.mps: "meters per second",
    },
    UnitType.distFine: {
      DisplayUnitsDist.imperial: "feet",
      DisplayUnitsDist.metric: "meters",
    },
    UnitType.distCoarse: {
      DisplayUnitsDist.imperial: "miles",
      DisplayUnitsDist.metric: "kilometers",
    },
    UnitType.fuel: {
      DisplayUnitsFuel.liter: "liters",
      DisplayUnitsFuel.gal: "gallons",
    }
  }
};

String getUnitStr(UnitType type, {bool lexical = false}) {
  switch (type) {
    case UnitType.speed:
      return _unitStr[lexical]![type][_unitSpeed];
    case UnitType.vario:
      return _unitStr[lexical]![type][_unitVario];
    case UnitType.distFine:
      return _unitStr[lexical]![type][_unitDist];
    case UnitType.distCoarse:
      return _unitStr[lexical]![type][_unitDist];
    case UnitType.fuel:
      return _unitStr[lexical]![type][_unitFuel];
    default:
      return "";
  }
}

/// Map of converter functions
/// `double => double`
Map<UnitType, double Function(double)> unitConverters = {
  UnitType.speed: (double value) => value,
  UnitType.vario: (double value) => value,
  UnitType.distFine: (double value) => value,
  UnitType.distCoarse: (double value) => value,
  UnitType.fuel: (double value) => value,
};

var _unitSpeed = DisplayUnitsSpeed.values.first;
var _unitVario = DisplayUnitsVario.values.first;
var _unitDist = DisplayUnitsDist.values.first;
var _unitFuel = DisplayUnitsFuel.values.first;

/// Reconfigure the unit converter functions for different destination types
void configUnits({DisplayUnitsSpeed? speed, DisplayUnitsVario? vario, DisplayUnitsDist? dist, DisplayUnitsFuel? fuel}) {
  // Remember the unit types selected
  _unitSpeed = speed ?? _unitSpeed;
  _unitVario = vario ?? _unitVario;
  _unitDist = dist ?? _unitDist;
  _unitFuel = fuel ?? _unitFuel;

  // --- Speed
  if (speed != null) {
    switch (speed) {
      case DisplayUnitsSpeed.mph:
        unitConverters[UnitType.speed] = (double value) => value * 3.6 * km2Miles;
        break;
      case DisplayUnitsSpeed.kph:
        unitConverters[UnitType.speed] = (double value) => value * 3.6;
        break;
      case DisplayUnitsSpeed.kts:
        unitConverters[UnitType.speed] = (double value) => value * 1.943844;
        break;
      case DisplayUnitsSpeed.mps:
        unitConverters[UnitType.speed] = (double value) => value;
        break;
      default:
        Exception("Unsupported unit");
        break;
    }
  }

  // --- Vario
  if (vario != null) {
    switch (vario) {
      case DisplayUnitsVario.fpm:
        unitConverters[UnitType.vario] = (double value) => value * 60 * meters2Feet;
        break;
      case DisplayUnitsVario.mps:
        unitConverters[UnitType.vario] = (double value) => value;
        break;
      default:
        Exception("Unsupported unit");
        break;
    }
  }

  // --- Dist
  if (dist != null) {
    switch (dist) {
      case DisplayUnitsDist.imperial:
        unitConverters[UnitType.distFine] = (double value) => value * meters2Feet;
        unitConverters[UnitType.distCoarse] = (double value) => value * meters2Miles;
        break;
      case DisplayUnitsDist.metric:
        unitConverters[UnitType.distFine] = (double value) => value;
        unitConverters[UnitType.distCoarse] = (double value) => value / 1000;
        break;
      default:
        Exception("Unsupported unit");
        break;
    }
  }

// --- Fuel
  if (fuel != null) {
    switch (fuel) {
      case DisplayUnitsFuel.gal:
        unitConverters[UnitType.fuel] = (double value) => value / 3.785411784;
        break;
      case DisplayUnitsFuel.liter:
        unitConverters[UnitType.fuel] = (double value) => value;
        break;
      default:
        Exception("Unsupported unit");
        break;
    }
  }
}

String printHrMinLexical(Duration duration) {
  int hr = duration.inHours;
  int min = duration.inMinutes - duration.inHours * 60;

  if (hr > 0) {
    return "$hr hour${hr == 1 ? "" : "s"}${min > 0 ? " $min minute${min == 1 ? "" : "s"}" : ""}";
  } else {
    return "$min minute${min == 1 ? "" : "s"}";
  }
}

TextSpan richHrMin({required Duration? duration, TextStyle? valueStyle, TextStyle? unitStyle, bool longUnits = false}) {
  if (duration == null) {
    return TextSpan(text: "∞", style: valueStyle);
  } else {
    int hr = duration.inHours;
    int min = duration.inMinutes - duration.inHours * 60;

    if (hr > 0) {
      return TextSpan(children: [
        TextSpan(text: hr.toString(), style: valueStyle),
        TextSpan(text: longUnits ? "hr " : "h ", style: unitStyle ?? valueStyle),
        TextSpan(text: min.toString(), style: valueStyle),
        TextSpan(text: longUnits ? "min" : "m", style: unitStyle ?? valueStyle),
      ]);
    } else {
      return TextSpan(children: [
        TextSpan(text: min.toString(), style: valueStyle),
        TextSpan(text: "min", style: unitStyle ?? valueStyle),
      ]);
    }
  }
}

TextSpan richMinSec(
    {required Duration? duration, TextStyle? valueStyle, TextStyle? unitStyle, bool longUnits = false}) {
  if (duration == null) {
    return TextSpan(text: "∞", style: valueStyle);
  } else {
    int min = duration.inMinutes;
    int sec = duration.inSeconds - duration.inMinutes * 60;

    if (min > 0) {
      return TextSpan(children: [
        TextSpan(text: min.toString(), style: valueStyle),
        TextSpan(text: longUnits ? "min " : "m ", style: unitStyle ?? valueStyle),
        TextSpan(text: sec.toString(), style: valueStyle),
        TextSpan(text: longUnits ? "sec" : "s", style: unitStyle ?? valueStyle),
      ]);
    } else {
      return TextSpan(children: [
        TextSpan(text: sec.toString(), style: valueStyle),
        TextSpan(text: "sec", style: unitStyle ?? valueStyle),
      ]);
    }
  }
}

/// Print a double but remove unecessary trailing zeros.
String printDoubleSimple(double value, {decimals = 1}) {
  return value
      .toStringAsFixed(decimals)
      .replaceAllMapped(RegExp(r"(?:(\.\d*?[1-9]+)|\.)0*$"), (match) => match.group(1) ?? "");
}

String printDouble({required double value, required int digits, required int decimals, double? autoDecimalThresh}) {
  if (value.isInfinite) return "∞";
  if (!value.isFinite) return "?";
  if (autoDecimalThresh != null && value.abs() < autoDecimalThresh) decimals++;
  final int mag = (pow(10, digits + decimals) - 1).round();
  final double decPwr = pow(10, decimals).toDouble();
  return ((min(mag, max(-mag, value * decPwr))).round() / decPwr).toStringAsFixed(max(0, decimals));
}

String printDoubleLexical(
    {required double value, double halfThreshold = 10, double quarterThreshold = 2, double eighthThreshold = 0.5}) {
  if (!value.isFinite) return "";

  if (value < eighthThreshold) {
    final numerator = ((value % 1.0) * 8).round();
    if (numerator % 2 == 1) {
      return "${value.floor() > 0 ? "${value.floor()} and " : ""}$numerator eighth${numerator == 1 ? "" : "s"}";
    }
  }
  if (value < quarterThreshold) {
    final numerator = ((value % 1.0) * 4).round();
    if (numerator % 2 == 1) {
      return "${value.floor() > 0 ? "${value.floor()} and " : ""}$numerator quarter${numerator == 1 ? "" : "s"}";
    }
  }
  if (value < halfThreshold) {
    final numerator = ((value % 1.0) * 2).round();
    if (numerator % 2 == 1) {
      return "${value.floor() > 0 ? "${value.floor()} and " : ""}a half";
    }
  }

  return "${value.round()}";
}

TextSpan richValue(UnitType type, double value,
    {int digits = 5, int decimals = 0, TextStyle? valueStyle, TextStyle? unitStyle, double? autoDecimalThresh}) {
  // Cases for increasing decimals

  if (type == UnitType.vario && _unitVario == DisplayUnitsVario.mps ||
      type == UnitType.speed && _unitSpeed == DisplayUnitsVario.mps) decimals++;

  double printValue = unitConverters[type]!(value);

  // Make the textspan
  return TextSpan(children: [
    TextSpan(
        text: printDouble(value: printValue, digits: digits, decimals: decimals, autoDecimalThresh: autoDecimalThresh),
        style: valueStyle),
    TextSpan(text: getUnitStr(type), style: unitStyle),
  ]);
}
