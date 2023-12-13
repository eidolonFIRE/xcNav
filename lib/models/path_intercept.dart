import 'package:latlong2/latlong.dart';

class PathIntercept {
  final int index;
  final LatLng latlng;

  /// Distance to intercept
  final double dist;

  /// Radians
  final double? hdg;
  PathIntercept({required this.index, required this.latlng, required this.dist, this.hdg});
}
