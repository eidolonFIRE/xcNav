/// When time is -1, there is no solution... (infinite eta)
class ETA {
  late double distance;
  late int time;

  ETA(this.distance, this.time);
  ETA.fromSpeed(this.distance, double speed) {
    if (speed > 0) {
      time = distance * 1000 ~/ speed;
    } else {
      time = -1;
    }
  }

  ETA operator +(ETA other) {
    final retTime = (time < 0 || other.time < 0) ? -1 : time + other.time;
    return ETA(distance + other.distance, retTime);
  }

  ETA operator -(ETA other) {
    final retTime = (time < 0 || other.time < 0) ? -1 : time + other.time;
    return ETA(distance - other.distance, retTime);
  }
}
