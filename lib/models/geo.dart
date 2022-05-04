import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// --- Constant unit converters
const km2Miles = 0.621371;
const meters2Feet = 3.28084;
const meters2Miles = km2Miles / 1000;

Distance latlngCalc = const Distance(roundResult: false);

class PathIntercept {
  final int index;
  final double ratio;
  final LatLng latlng;
  PathIntercept(this.index, this.ratio, this.latlng);
}

class Geo {
  double lat = 0;
  double lng = 0;

  /// Meters
  double alt = 0;
  int time = 0; // milliseconds
  /// Radians
  double hdg = 0; // radians
  double spd = 0; // meters/sec
  double vario = 0; // meters/sec

  LatLng get latLng => LatLng(lat, lng);

  Geo();
  Geo.fromValues(
      this.lat, this.lng, this.alt, this.time, this.hdg, this.spd, this.vario);

  Geo.fromPosition(Position location, Geo? prev) {
    lat = location.latitude;
    lng = location.longitude;
    alt = location.altitude;
    time = location.timestamp?.millisecondsSinceEpoch ?? 0;

    if (prev != null && prev.time < time) {
      // prefer our own calculations
      final double dist =
          latlngCalc.distance(LatLng(prev.lat, prev.lng), LatLng(lat, lng));

      spd = dist / (time - prev.time) * 1000;
      if (dist < 1) {
        hdg = prev.hdg;
      } else {
        hdg = latlngCalc.bearing(LatLng(prev.lat, prev.lng), LatLng(lat, lng)) *
            3.1415926 /
            180;
      }

      vario = (alt - prev.alt) / (time - prev.time) * 1000;
    } else {
      spd = location.speed;
      hdg = location.heading;
      vario = 0;
    }
  }

  Geo.fromJson(dynamic data) {
    lat = data["lat"];
    lng = data["lng"];
    alt = data["alt"];
    time = data["time"];
    hdg = data["hdg"];
    spd = data["spd"];
    vario = data["vario"];
  }

  /// Find distance to and location of the best intercept to path.
  /// (Nearest point that doesn't have acute angle between next point and this point)
  PathIntercept nearestPointOnPath(List<LatLng> path, bool isReversed) {
    // Scan through all line segments and find intercept
    int matchIndex = 0;
    double matchdist = double.infinity;

    for (int index = isReversed ? path.length - 1 : 0;
        isReversed ? (index > 0) : (index < path.length);
        index += isReversed ? -1 : 1) {
      final dist = latlngCalc.distance(latLng, path[index]);
      double angleToNext = double.nan;
      if (isReversed ? (index > 0) : (index < path.length - 1)) {
        double delta = latlngCalc.bearing(path[index], latLng) -
            latlngCalc.bearing(
                path[index], path[index + (isReversed ? -1 : 1)]);
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        angleToNext = delta.abs();
      }
      if (dist < matchdist && (angleToNext == double.nan || angleToNext > 90)) {
        matchdist = dist;
        matchIndex = index;
        // debugPrint("match: $index) $dist  $angleToNext");
      }
    }
    return PathIntercept(matchIndex, matchdist, path[matchIndex]);
  }

  double distanceTo(Geo other) {
    return latlngCalc.distance(other.latLng, latLng);
  }

  double distanceToLatlng(LatLng other) {
    return latlngCalc.distance(other, latLng);
  }

  static double distanceBetween(LatLng a, LatLng b) {
    return latlngCalc.distance(a, b);
  }

  Map<String, num> toJson() {
    return {
      "lat": lat,
      "lng": lng,
      "alt": alt,
      "time": time,
      "hdg": hdg,
      "spd": spd,
      "vario": vario,
    };
  }
}
