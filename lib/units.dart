import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/util.dart';

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
  fps,
  mps,
}

enum DisplayUnitsDist {
  imperial,
  metric,
}

enum DisplayUnitsFuel {
  liter,
  gal,
  kWh,
}

String getUnitStr(UnitType type, {bool lexical = false, dynamic override}) {
  switch (type) {
    case UnitType.speed:
      return "unit.${lexical ? "long" : "short"}.${type.toString()}.${(override ?? _unitSpeed).toString().split(".").last}"
          .tr();
    case UnitType.vario:
      return "unit.${lexical ? "long" : "short"}.${type.toString()}.${(override ?? _unitVario).toString().split(".").last}"
          .tr();
    case UnitType.distFine:
      return "unit.${lexical ? "long" : "short"}.${type.toString()}.${(override ?? _unitDist).toString().split(".").last}"
          .tr();
    case UnitType.distCoarse:
      return "unit.${lexical ? "long" : "short"}.${type.toString()}.${(override ?? _unitDist).toString().split(".").last}"
          .tr();
    case UnitType.fuel:
      return "unit.${lexical ? "long" : "short"}.${type.toString()}.${(override ?? _unitFuel).toString().split(".").last}"
          .tr();
  }
}

String get fuelRateStr {
  if (_unitFuel == DisplayUnitsFuel.kWh) {
    return " kW";
  } else {
    return " ${getUnitStr(UnitType.fuel)}/${"time.hour.short.one".tr()}";
  }
}

String get fuelEffStr => " ${getUnitStr(UnitType.distCoarse)}/${getUnitStr(UnitType.fuel)}";

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
    }
  }

  // --- Vario
  if (vario != null) {
    switch (vario) {
      case DisplayUnitsVario.fpm:
        unitConverters[UnitType.vario] = (double value) => value * 60 * meters2Feet;
        break;
      case DisplayUnitsVario.fps:
        unitConverters[UnitType.vario] = (double value) => value * meters2Feet;
        break;
      case DisplayUnitsVario.mps:
        unitConverters[UnitType.vario] = (double value) => value;
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
      case DisplayUnitsFuel.kWh:
        unitConverters[UnitType.fuel] = (double value) => value;
    }
  }
}

String printHrMinLexical(Duration duration) {
  int hr = duration.inHours;
  int min = duration.inMinutes - duration.inHours * 60;

  if (hr > 0) {
    return "$hr ${"time.hour.long".plural(hr)} $min ${"time.minute.long".plural(min)}";
  } else {
    return "$min ${"time.minute.long".plural(min)}";
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
        TextSpan(
            text: "${"time.hour.${longUnits ? "long" : "short"}".plural(hr)} ",
            style: resolveSmallerStyle(unitStyle, valueStyle)),
        TextSpan(text: min.toString(), style: valueStyle),
        TextSpan(
            text: "${"time.minute.${longUnits ? "long" : "short"}".plural(min)} ",
            style: resolveSmallerStyle(unitStyle, valueStyle)),
      ]);
    } else {
      return TextSpan(children: [
        TextSpan(text: min.toString(), style: valueStyle),
        TextSpan(
            text: "${"time.minute.${longUnits ? "long" : "short"}".plural(min)} ",
            style: resolveSmallerStyle(unitStyle, valueStyle)),
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
        TextSpan(
            text: "${"time.minute.${longUnits ? "long" : "short"}".plural(min)} ",
            style: resolveSmallerStyle(unitStyle, valueStyle)),
        TextSpan(text: sec.toString(), style: valueStyle),
        TextSpan(
            text: "${"time.second.${longUnits ? "long" : "short"}".plural(sec)} ",
            style: resolveSmallerStyle(unitStyle, valueStyle)),
      ]);
    } else {
      return TextSpan(children: [
        TextSpan(text: sec.toString(), style: valueStyle),
        TextSpan(
            text: "${"time.second.${longUnits ? "long" : "short"}".plural(sec)} ",
            style: resolveSmallerStyle(unitStyle, valueStyle)),
      ]);
    }
  }
}

/// Trim unecessary zeros from a string number.
String trimZeros(String text) {
  return text.replaceAllMapped(RegExp(r"(?:(\.\d*?[1-9]+)|\.)0*$"), (match) => match.group(1) ?? "");
}

/// Print a double but remove unecessary trailing zeros.
String printDoubleSimple(double value, {decimals = 1}) {
  return trimZeros(value.toStringAsFixed(decimals));
}

/// autoDecimalThresh: auto add decimal when value is less than threshold
String printDouble(
    {required double value,
    required int digits,
    required int decimals,
    double? autoDecimalThresh,
    bool removeZeros = true}) {
  if (value.isInfinite) return "∞";
  if (!value.isFinite) return "?";
  if (autoDecimalThresh != null && value.abs() < autoDecimalThresh) decimals++;
  final int mag = (pow(10, digits + decimals) - 1).round();
  final double decPwr = pow(10, decimals).toDouble();
  final retval = ((min(mag, max(-mag, value * decPwr))).round() / decPwr).toStringAsFixed(max(0, decimals));
  return removeZeros ? trimZeros(retval) : retval;
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

/// Convert a double with units to string.
String? printValue(UnitType type, double? value,
    {int digits = 5, int decimals = 2, double? autoDecimalThresh, bool removeZeros = true}) {
  if (value == null) return null;
  return printDouble(
      value: unitConverters[type]!(value),
      digits: digits,
      decimals: decimals,
      autoDecimalThresh: autoDecimalThresh,
      removeZeros: removeZeros);
}

/// Attempt to parse a value and convert it to standard unit.
double? parseDoubleValue(UnitType type, String? value) {
  final parsed = parseAsDouble(value);
  if (parsed != null) {
    return parsed / unitConverters[type]!(1);
  }
  return null;
}

TextSpan richValue(UnitType type, double value,
    {int digits = 5,
    int decimals = 0,
    TextStyle? valueStyle,
    TextStyle? unitStyle,
    double? autoDecimalThresh,
    bool removeZeros = true}) {
  // Cases for increasing decimals

  if (type == UnitType.vario && _unitVario == DisplayUnitsVario.mps ||
      type == UnitType.speed && _unitSpeed == DisplayUnitsSpeed.mps) {
    decimals++;
  }

  double printValue = unitConverters[type]!(value);

  // Make the textspan
  return TextSpan(children: [
    TextSpan(
        text: printDouble(
            value: printValue,
            digits: digits,
            decimals: decimals,
            autoDecimalThresh: autoDecimalThresh,
            removeZeros: removeZeros),
        style: valueStyle),
    TextSpan(text: " ${getUnitStr(type)}", style: resolveSmallerStyle(unitStyle, valueStyle)),
  ]);
}
