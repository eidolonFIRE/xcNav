import 'package:location/location.dart';
import 'package:latlong2/latlong.dart';



LatLng locationToLatLng(LocationData location) {
  return LatLng(location.latitude!, location.longitude!);
}


class Geo {

  static var calc = const Distance(roundResult: false);

  double lat = 0;
  double lng = 0;
  double alt = 0;
  double time = 0;
  double hdg = 0;
  double spd = 0;
  double vario = 0;


  Geo();
  Geo.fromValues(this.lat, this.lng, this.alt, this.time, this.hdg, this.spd, this.vario);
  Geo.fromLocationData(LocationData location, Geo? prev) {
    lat = location.latitude ?? 0;
    lng = location.longitude ?? 0;
    alt = location.altitude ?? 0;
    time = location.time ?? 0;
    

    if (prev != null && prev.time < time) {
      // prefer our own calculations
      // spd = location
      final double dist = calc.distance(LatLng(prev.lat, prev.lng), LatLng(lat, lng));

      // TODO: get units correct
      spd = dist / (time - prev.time) * 3600;
      if (dist < 1) {
        hdg = prev.hdg;
      } else {
        hdg = calc.bearing(LatLng(prev.lat, prev.lng), LatLng(lat, lng)) * 3.1415926 / 180;
      }

      vario = (alt - prev.alt) / (time - prev.time);
    } else {
      spd = location.speed ?? 0;
      hdg = location.heading ?? 0;
      vario = 0;
    }

  }

  LatLng get latLng{
    return LatLng(lat, lng);
  }
}
