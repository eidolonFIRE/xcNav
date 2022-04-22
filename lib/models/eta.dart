import 'geo.dart';

String hmm(int milliseconds) {
  final dur = Duration(milliseconds: milliseconds);
  final hr = dur.inHours;
  return "$hr:${(dur.inMinutes - hr * 60).toString().padLeft(2, "0")}";
}

class ETA {
  late double distance;
  late int time;

  ETA(this.distance, this.time);
  ETA.fromSpeed(this.distance, double speed) {
    if (speed > 0) {
      time = distance * 1000 ~/ speed;
    } else {
      time = 0;
    }
  }

  String miles() {
    return (distance * km2Miles / 1000).toStringAsFixed(1);
  }

  String hhmm() {
    if (time == 0) {
      // TODO: should this return blank?
      return "-:--";
    } else {
      return hmm(time);
    }
  }

  ETA operator +(ETA other) {
    return ETA(distance + other.distance, time + other.time);
  }

  ETA operator -(ETA other) {
    return ETA(distance - other.distance, time - other.time);
  }
}
