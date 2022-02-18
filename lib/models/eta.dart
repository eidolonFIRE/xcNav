import 'geo.dart';

RegExp hhmmFormat = RegExp("([0-9]+:[0-9]+)");

class ETA {
  late double distance;
  late int time;

  ETA(this.distance, this.time);
  ETA.fromSpeed(this.distance, double speed) {
    // TODO: figure out the speed units
    time = distance * 1000 ~/ speed;
  }

  String miles() {
    return (distance * km2Miles / 1000).toStringAsFixed(1);
  }

  String hhmm() {
    if (time == 0) {
      // TODO: should this return blank?
      return "-:--";
    } else {
      return hhmmFormat
          .firstMatch(Duration(milliseconds: time).toString())!
          .group(0)!;
    }
  }

  ETA operator +(ETA other) {
    return ETA(distance + other.distance, time + other.time);
  }

  ETA operator -(ETA other) {
    return ETA(distance - other.distance, time - other.time);
  }
}
