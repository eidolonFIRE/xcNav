import 'package:flutter/material.dart';

import 'package:location/location.dart';

import '../util/geo.dart';



class MyTelemetry with ChangeNotifier {

  // Live Readings
  Geo geo = Geo();

  // Calculated
  Geo? geoPrev;

  void updateGeo(LocationData location) {
    print("${location.elapsedRealtimeNanos}) ${location.latitude}, ${location.longitude}, ${location.altitude}");
    geoPrev = geo;
    geo = Geo.fromLocationData(location, geoPrev);



    notifyListeners();
  }



}
