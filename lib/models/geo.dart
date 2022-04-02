import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart';
import 'package:latlong2/latlong.dart';

// --- Constant unit converters
const km2Miles = 0.621371;
const meters2Feet = 3.28084;
const meter2Mile = km2Miles / 1000;

LatLng locationToLatLng(LocationData location) {
  return LatLng(location.latitude!, location.longitude!);
}

Distance latlngCalc = const Distance(roundResult: false);

class Geo {
  static var calc = const Distance(roundResult: false);

  double lat = 0;
  double lng = 0;
  double alt = 0;
  int time = 0; // milliseconds
  double hdg = 0; // radians
  double spd = 0; // meters/sec
  double vario = 0; // meters/sec

  Geo();
  Geo.fromValues(
      this.lat, this.lng, this.alt, this.time, this.hdg, this.spd, this.vario);
  Geo.fromLocationData(LocationData location, Geo? prev) {
    lat = location.latitude ?? 0;
    lng = location.longitude ?? 0;
    alt = location.altitude ?? 0;
    time = location.time?.toInt() ?? 0;

    if (prev != null && prev.time < time) {
      // prefer our own calculations
      // spd = location
      final double dist =
          calc.distance(LatLng(prev.lat, prev.lng), LatLng(lat, lng));

      // TODO: get units correct
      spd = dist / (time - prev.time) * 1000;
      if (dist < 1) {
        hdg = prev.hdg;
      } else {
        hdg = calc.bearing(LatLng(prev.lat, prev.lng), LatLng(lat, lng)) *
            3.1415926 /
            180;
      }

      vario = (alt - prev.alt) / (time - prev.time) * 1000;
    } else {
      spd = location.speed ?? 0;
      hdg = location.heading ?? 0;
      vario = 0;
    }
  }

  Geo.fromPosition(Position location, Geo? prev) {
    lat = location.latitude;
    lng = location.longitude;
    alt = location.altitude;
    time = location.timestamp?.millisecondsSinceEpoch ?? 0;

    if (prev != null && prev.time < time) {
      // prefer our own calculations
      // spd = location
      final double dist =
          calc.distance(LatLng(prev.lat, prev.lng), LatLng(lat, lng));

      // TODO: get units correct
      spd = dist / (time - prev.time) * 1000;
      if (dist < 1) {
        hdg = prev.hdg;
      } else {
        hdg = calc.bearing(LatLng(prev.lat, prev.lng), LatLng(lat, lng)) *
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

  double distanceTo(Geo other) {
    return calc.distance(LatLng(other.lat, other.lng), LatLng(lat, lng));
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

  LatLng get latLng {
    return LatLng(lat, lng);
  }
}
