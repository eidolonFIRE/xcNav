import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/models/path_intercept.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

class Geo {
  double lat = 0;
  double lng = 0;

  /// Meters
  double alt = 0;
  double altGps = 0;

  /// Ground Elevation
  double? _gnd;
  double? prevGnd;
  set ground(double? value) {
    _gnd = value;
  }

  ///
  double? get ground => _gnd ?? prevGnd;

  /// milliseconds since epoch
  int time = 0;

  /// Radians
  double hdg = 0;

  /// meters/sec
  double spd = 0;

  /// meters/sec
  double spdSmooth = 0;

  /// meters/sec
  double vario = 0;

  /// meters/sec
  double varioSmooth = 0;

  LatLng get latlng => LatLng(lat, lng);

  Geo({this.lat = 0, this.lng = 0, this.alt = 0, int? timestamp, this.hdg = 0, this.spd = 0, this.vario = 0}) {
    time = timestamp ?? DateTime.now().millisecondsSinceEpoch;
  }

  Geo.fromPosition(Position location, Geo? prev, BarometerEvent? baro, BarometerEvent? baroAmbient) {
    lat = location.latitude;
    lng = location.longitude;
    time = location.timestamp.millisecondsSinceEpoch;
    altGps = location.altitude;

    if (prev != null && prev.time < time) {
      // prefer our own calculations
      final double dist = latlngCalc.distance(LatLng(prev.lat, prev.lng), LatLng(lat, lng));

      spd = dist / (time - prev.time) * 1000;
      if (dist < 1) {
        hdg = prev.hdg;
      } else {
        hdg = latlngCalc.bearing(LatLng(prev.lat, prev.lng), LatLng(lat, lng)) * 3.1415926 / 180;
      }
    } else {
      spd = prev?.spd ?? location.speed;
      hdg = prev?.hdg ?? location.heading;
    }

    if (baro != null) {
      // altitude / vario filtering
      final double amb = baroAmbient?.pressure ?? 1013.25;
      alt = 145366.45 * (1 - pow(baro.pressure / amb, 0.190284)) / meters2Feet;
    } else {
      alt = location.altitude;
    }

    if (prev != null && prev.time < time) {
      vario = (alt - prev.alt) / (time - prev.time) * 1000;
      if (vario.isNaN || vario.isInfinite) vario = 0;
      // Blend vario with previous vario reading to offer some mild smoothing
      if (prev.varioSmooth.isFinite && vario.abs() < 99) varioSmooth = vario * 0.2 + prev.varioSmooth * 0.8;
      spdSmooth = spd * 0.1 + prev.spdSmooth * 0.9;
    } else {
      vario = prev?.vario ?? 0;
      spdSmooth = prev?.spdSmooth ?? spd;
    }
  }

  /// Find distance to and location of the best intercept to path.
  /// (Nearest point that doesn't have acute angle between next point and this point)
  PathIntercept getIntercept(List<LatLng> path, {bool isReversed = false}) {
    // Early out
    if (path.length == 1) {
      return PathIntercept(index: 0, latlng: path[0], dist: latlngCalc.distance(latlng, path[0]));
    }

    // Scan through all line segments and find intercept
    int matchIndex = isReversed ? 0 : path.length - 1;
    double matchdist = double.infinity;

    for (int index = isReversed ? path.length - 1 : 0;
        isReversed ? (index > 0) : (index < path.length);
        index += isReversed ? -1 : 1) {
      final dist = latlngCalc.distance(latlng, path[index]);
      double angleToNext = double.nan;
      if (isReversed ? (index > 0) : (index < path.length - 1)) {
        double delta = latlngCalc.bearing(path[index], latlng) -
            latlngCalc.bearing(path[index], path[index + (isReversed ? -1 : 1)]);
        delta = (delta + 180) % 360 - 180;
        angleToNext = delta.abs();
      }
      if (dist < matchdist && (angleToNext.isNaN || angleToNext > 90)) {
        matchdist = dist;
        matchIndex = index;
        // debugPrint("match: $index) $dist  $angleToNext");
      }
    }
    return PathIntercept(
        index: isReversed ? path.length - 1 - matchIndex : matchIndex,
        latlng: path[matchIndex],
        dist: latlngCalc.distance(latlng, path[matchIndex]));
  }

  double distanceTo(Geo other) {
    return latlngCalc.distance(other.latlng, latlng);
  }

  double distanceToLatlng(LatLng other) {
    return latlngCalc.distance(other, latlng);
  }

  /// Returns radians +/- pi
  double relativeHdg(Geo other) {
    final delta = latlngCalc.bearing(latlng, other.latlng) * pi / 180 - hdg;
    return (delta + pi) % (2 * pi) - pi;
  }

  double relativeHdgLatlng(LatLng other) {
    final delta = latlngCalc.bearing(latlng, other) * pi / 180 - hdg;
    return (delta + pi) % (2 * pi) - pi;
  }

  static double distanceBetween(LatLng a, LatLng b) {
    return latlngCalc.distance(a, b);
  }

  Map<String, num> toJson() {
    final dict = {
      // 7-dig ~= 1cm precision
      "lat": roundToDigits(lat, 7),
      "lng": roundToDigits(lng, 7),
      // 2-dig ~= 1cm
      "alt": roundToDigits(alt, 2),
      "time": time,
      "hdg": roundToDigits(hdg, 2),
      "spd": roundToDigits(spd, 3),
      "vario": roundToDigits(vario, 3),
    };
    if (ground != null) {
      dict["ground"] = roundToDigits(ground!, 2);
    }
    return dict;
  }

  Geo.fromJson(Map<String, dynamic> data) {
    lat = parseAsDouble(data["lat"])!;
    lng = parseAsDouble(data["lng"])!;
    alt = parseAsDouble(data["alt"]) ?? 0;
    time = data["time"] as int;
    hdg = parseAsDouble(data["hdg"]) ?? 0;
    spd = parseAsDouble(data["spd"]) ?? 0;
    vario = parseAsDouble(data["vario"]) ?? 0;
    ground = parseAsDouble(data["ground"]);
  }
}
