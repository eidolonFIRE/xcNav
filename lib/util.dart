import 'dart:io';
import 'dart:math';

import 'package:bisection/bisect.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:xcnav/models/path_intercept.dart';
import 'package:xcnav/datadog.dart';

Distance latlngCalc = const Distance(roundResult: false);

late PackageInfo version;

void setSystemUI() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      // statusBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top]);
}

/// a or b but smaller by a factor
TextStyle? resolveSmallerStyle(TextStyle? a, TextStyle? b, {double factor = 0.6}) {
  if (a != null || b != null) {
    return a ?? b?.merge(TextStyle(fontSize: b.fontSize != null ? (b.fontSize! * factor) : null));
  } else {
    return null;
  }
}

extension IterableConvolve<T> on Iterable<T> {
  Iterable<R> convolve<R>(R? Function(T a, T b) action) sync* {
    final it = iterator;
    T? prev;
    while (it.moveNext()) {
      if (prev != null) {
        final ret = action(prev, it.current);
        if (ret != null) yield ret;
      }
      prev = it.current;
    }
  }
}

class TimestampDouble {
  /// Milliseconds since epoch
  final int time;
  final double value;

  TimestampDouble(this.time, this.value);

  @override
  bool operator ==(Object other) {
    if (other is TimestampDouble) {
      return other.time == time && other.value == value;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => time.hashCode + value.hashCode;
}

class Range<T> {
  final T start;
  final T end;
  Range(this.start, this.end);
  @override
  String toString() {
    return "Range($start, $end)";
  }
}

class HistogramData<T> {
  final Range<T> range;
  final List<int> values;
  HistogramData(this.range, this.values);
}

/// Round to number of digits
double roundToDigits(double value, double digits) {
  return (value * pow(10, digits)).round() / pow(10, digits);
}

/// int, double, or String -> String
String? parseAsString(dynamic value) {
  if (value is String) return value;
  if (value is int) return value.toString();
  if (value is double) return value.toString();
  if (value is bool) return value.toString();
  return null;
}

double? parseAsDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String && value.isNotEmpty) {
    try {
      return double.parse(value);
    } catch (err, trace) {
      final msg = "failed to parse double $value";
      info(msg, errorMessage: err.toString(), errorStackTrace: trace);
    }
  }

  return null;
}

int? parseAsInt(dynamic value) {
  if (value is double) return value.round();
  if (value is int) return value;
  if (value is String && value.isNotEmpty) {
    try {
      return int.parse(value);
    } catch (err, trace) {
      final msg = "failed to parse int $value";
      info(msg, errorMessage: err.toString(), errorStackTrace: trace);
    }
  }

  return null;
}

LatLng clampLatLng(double latitude, double longitude) {
  return LatLng(min(90, max(-90, latitude)), min(180, max(-180, longitude)));
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
    final file = File(filename);
    await file.create(recursive: true);
    await file.writeAsString(data);
    return Future.value(true);
  } catch (err, trace) {
    error("Failed to save file $filename.",
        errorMessage: err.toString(), errorStackTrace: trace, attributes: {"dataLength": data.length});
    return Future.value(false);
  }
}

int nearestIndex(List<num> a, num value) {
  if (a.length == 1) return 0;
  final b = bisect<num>(a, value);
  if (b == 0) return 0;
  if (b >= a.length) return a.length - 1;
  return (a[b] - value <= value - a[b - 1]) ? b : b - 1;
}

LatLngBounds padLatLngBounds(LatLngBounds bounds, double bufferRatio) {
  final heightBuffer = (bounds.southWest.latitude - bounds.northEast.latitude).abs() * bufferRatio;
  final widthBuffer = (bounds.southWest.longitude - bounds.northEast.longitude).abs() * bufferRatio;

  final point1 = LatLng((90 + bounds.southWest.latitude - heightBuffer) % 180 - 90,
      (180 + bounds.southWest.longitude - widthBuffer) % 360 - 180);
  final point2 = LatLng((90 + bounds.northEast.latitude + heightBuffer) % 180 - 90,
      (180 + bounds.northEast.longitude + widthBuffer) % 360 - 180);

  return LatLngBounds(point1, point2);
}

/// Return the difference in radian heading. (+/- pi)
double deltaHdg(double a, double b) {
  return (a - b + pi) % (2 * pi) - pi;
}

/// Calculate resulting vector when traveling straight with wind.
/// If blown off course, collective will have X component.
Offset calcCollective(Offset windVector, double airspeed) {
  double collectiveMag = 0;
  late Offset collective;
  final comp = airspeed * airspeed - windVector.dx * windVector.dx;
  if (comp >= 0) {
    collectiveMag = -sqrt(comp) + windVector.dy;
    collective = Offset(0, collectiveMag);
  }
  if (comp < 0 || collectiveMag > 0) {
    collectiveMag = sqrt(windVector.distance * windVector.distance - airspeed * airspeed);
    final inscribedTheta = asin(airspeed / windVector.distance);
    final collectiveTheta = windVector.direction + inscribedTheta * (windVector.dx < 0 ? 1 : -1);
    collective = Offset.fromDirection(collectiveTheta, collectiveMag);
  }
  return collective;
}

/// Travel down a path.
/// Note there is no caching for this call. It is not recommended to call this too frequently.
///
/// latlgns : Path to travel down.
///
/// spd : craft speed, m/s
///
/// windHdg, windSpd : wind forces acting on craft
///
/// duration : max duration down path
///
/// distance : max distance down path
PathIntercept? interpolateWithWind(List<LatLng> latlngs, double spd, double windHdg, double windSpd,
    {Duration? duration, double? distance}) {
  double sumDist = 0;
  Duration sumDur = Duration.zero;
  for (int index = 0; index < latlngs.length - 1; index++) {
    final stepDist = latlngCalc.distance(latlngs[index], latlngs[index + 1]);
    final stepBrg = latlngCalc.bearing(latlngs[index], latlngs[index + 1]);

    final collective = calcCollective(Offset.fromDirection(stepBrg / 180 * pi - windHdg - pi / 2, windSpd), spd);

    final stepTime = Duration(milliseconds: (stepDist / collective.distance * 1000).round());

    if ((distance != null && distance <= sumDist + stepDist) || (duration != null && duration <= sumDur + stepTime)) {
      // Intercept is in this segment
      if (stepTime <= Duration.zero) {
        // Headwind too strong, end at this point
        return PathIntercept(index: index, latlng: latlngs[index], dist: sumDist);
      } else {
        // Interpolate segment
        final remDist = min<double>(distance != null ? distance - sumDist : double.infinity,
            duration != null ? (duration - sumDur).inMilliseconds / 1000 * collective.distance : double.infinity);

        final latlng = latlngCalc.offset(latlngs[index], remDist, stepBrg);
        return PathIntercept(index: index, latlng: latlng, dist: 0);
      }
    } else {
      // Accumulate
      if (distance != null) sumDist += stepDist;
      if (duration != null) sumDur += stepTime;
    }
  }

  // No intercept found
  return null;
}

/// Return true if point is inside the polygon
bool polygonContainsPoint(LatLng point, List<LatLng> polygon) {
  final int numPoints = polygon.length;
  final double x = point.longitude, y = point.latitude;
  bool inside = false;

  // Store the first point in the polygon and initialize
  // the second point
  LatLng p1 = polygon[0];
  LatLng p2;

  if (numPoints < 3) return false;

  // Loop through each edge in the polygon
  for (int i = 1; i <= numPoints; i++) {
    // Get the next point in the polygon
    p2 = polygon[i % numPoints];

    // Check if the point is above the minimum y
    // coordinate of the edge
    if (y > min(p1.latitude, p2.latitude)) {
      // Check if the point is below the maximum y
      // coordinate of the edge
      if (y <= max(p1.latitude, p2.latitude)) {
        // Check if the point is to the left of the
        // maximum x coordinate of the edge
        if (x <= max(p1.longitude, p2.longitude)) {
          // Calculate the x-intersection of the
          // line connecting the point to the edge
          double xInter =
              (y - p1.latitude) * (p2.longitude - p1.longitude) / (p2.latitude - p1.latitude) + p1.longitude;

          // Check if the point is on the same
          // line as the edge or to the left of
          // the x-intersection
          if (p1.longitude == p2.longitude || x <= xInter) {
            // Flip the inside flag
            inside = !inside;
          }
        }
      }
    }

    // Store the current point as the first point for
    // the next iteration
    p1 = p2;
  }

  // Return the value of the inside flag
  return inside;
}

Map<String, num> latlngToJson(LatLng latlng) {
  return {
    "lat": latlng.latitude,
    "lng": latlng.longitude,
  };
}

LatLng? latlngFromJson(Map<String, dynamic> data) {
  final lat = parseAsDouble(data["lat"]);
  final lng = parseAsDouble(data["lng"]);
  if (lat != null && lng != null) {
    return LatLng(lat, lng);
  } else {
    error("Couldn't parse latlng", attributes: data);
    return null;
  }
}
