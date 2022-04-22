import 'package:latlong2/latlong.dart';

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

class FlightPlan {
  late final String _filename;
  late final bool goodFile;
  late final String title;
  late final List<Waypoint> waypoints;
  late final double length;

  get filename => _filename;

  FlightPlan.fromJson(String filename, dynamic data) {
    _filename = filename;

    try {
      List<dynamic> _dataSamples = data["waypoints"];
      waypoints = _dataSamples.map((e) => Waypoint.fromJson(e)).toList();

      title = data["title"];

      // --- Calculate Stuff
      double _length = 0;
      int? prevIndex;
      for (int i = 0; i < waypoints.length; i++) {
        // skip optional waypoints
        Waypoint wpIndex = waypoints[i];
        if (wpIndex.isOptional) continue;

        if (prevIndex != null) {
          // Will take the last point of the current waypoint, nearest point of the next
          LatLng prevLatlng = waypoints[prevIndex].latlng.first;
          _length += latlngCalc.distance(wpIndex.latlng.first, prevLatlng);

          // add path distance
          _length += wpIndex.length;
        }
        prevIndex = i;
      }
      length = _length;

      goodFile = true;
    } catch (e) {
      title = "Broken File!";
      goodFile = false;
    }
  }
}
