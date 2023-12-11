import 'package:latlong2/latlong.dart';

class Barb {
  final LatLng latlng;

  /// Radians
  late final double hdg;

  Barb(this.latlng, this.hdg);

  /// Init from compass bearing (degrees)
  Barb.fromBrg(this.latlng, double brg) {
    hdg = brg / 180 * pi;
  }
}
