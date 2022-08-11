import 'dart:math';
import 'package:flutter/material.dart';
import 'package:xcnav/models/geo.dart';

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

const Map<DisplayUnitsSpeed, String> unitStrSpeed = {
  DisplayUnitsSpeed.mph: " mph",
  DisplayUnitsSpeed.kts: " kts",
  DisplayUnitsSpeed.kph: " kph",
  DisplayUnitsSpeed.mps: " m/s",
};

const Map<DisplayUnitsVario, String> unitStrVario = {
  DisplayUnitsVario.fpm: " ft/m",
  DisplayUnitsVario.mps: " m/s",
};

const Map<DisplayUnitsDist, String> unitStrDistFine = {
  DisplayUnitsDist.imperial: " ft",
  DisplayUnitsDist.metric: " m",
};

const Map<DisplayUnitsDist, String> unitStrDistCoarse = {
  DisplayUnitsDist.imperial: " mi",
  DisplayUnitsDist.metric: " km",
};

const Map<DisplayUnitsDist, String> unitStrDistCoarseLexical = {
  DisplayUnitsDist.imperial: " mile",
  DisplayUnitsDist.metric: " kilometer",
};

const Map<DisplayUnitsFuel, String> unitStrFuel = {
  DisplayUnitsFuel.liter: " L",
  DisplayUnitsFuel.gal: " gal",
};

String printHrMin({Duration? duration, int? milliseconds}) {
  int t = milliseconds ?? duration?.inMilliseconds ?? 0;

  int hr = (t / 3600000).floor();
  int min = ((t - hr * 3600000) / 60000).floor();

  if (hr > 0) {
    return "${hr}h ${min}m";
  } else {
    return "$min min";
  }
}

String printHrMinLexical(Duration duration) {
  int hr = duration.inHours;
  int min = duration.inMinutes;

  if (hr > 0) {
    return "$hr hours $min minute${min == 1 ? "" : "s"}";
  } else {
    return "$min minute${min == 1 ? "" : "s"}";
  }
}

TextSpan richHrMin(
    {required Duration? duration, required TextStyle valueStyle, TextStyle? unitStyle, bool longUnits = false}) {
  if (duration == null) {
    return TextSpan(text: "∞", style: valueStyle);
  } else {
    int hr = duration.inHours;
    int min = duration.inMinutes;

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

String printValue({required double value, required int digits, required int decimals, double? autoDecimalThresh}) {
  if (!value.isFinite) return "?";
  if (autoDecimalThresh != null && value < autoDecimalThresh) decimals++;
  final int mag = (pow(10, digits) - 1).round();
  final double decPwr = pow(10, decimals).toDouble();
  return ((min(mag, max(-mag, value)) * decPwr).round() / decPwr).toStringAsFixed(decimals);
}

String printValueLexical(
    {required double value, double halfThreshold = 10, double quarterThreshold = 2, double eighthThreshold = 1}) {
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

double convertDistValueFine(DisplayUnitsDist mode, double value, {int? clampDigits}) {
  switch (mode) {
    case DisplayUnitsDist.imperial:
      return value * meters2Feet;
    case DisplayUnitsDist.metric:
      return value;
  }
}

double convertDistValueCoarse(DisplayUnitsDist mode, double value) {
  switch (mode) {
    case DisplayUnitsDist.imperial:
      return value * meters2Miles;
    case DisplayUnitsDist.metric:
      return value / 1000;
  }
}

double convertSpeedValue(DisplayUnitsSpeed mode, double value) {
  switch (mode) {
    case DisplayUnitsSpeed.mph:
      return value * 3.6 * km2Miles;
    case DisplayUnitsSpeed.kph:
      return value / 60 * 1000;
    case DisplayUnitsSpeed.kts:
      return value * 1.943844;
    case DisplayUnitsSpeed.mps:
      return value;
  }
}

double convertVarioValue(DisplayUnitsVario mode, double value) {
  switch (mode) {
    case DisplayUnitsVario.fpm:
      return value * 60 * meters2Feet;
    case DisplayUnitsVario.mps:
      return value;
  }
}

double convertFuelValue(DisplayUnitsFuel mode, double value) {
  switch (mode) {
    case DisplayUnitsFuel.gal:
      return value / 3.785411784;
    case DisplayUnitsFuel.liter:
      return value;
  }
}
