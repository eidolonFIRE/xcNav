import 'package:latlong2/latlong.dart';

class Waypoint {
  String name;
  List<LatLng> latlng;
  bool isOptional;
  String? icon;
  double? length;

  Waypoint(this.name, this.latlng, this.isOptional);
}
