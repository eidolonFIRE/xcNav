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

  ETA operator +(ETA other) {
    return ETA(distance + other.distance, time + other.time);
  }

  ETA operator -(ETA other) {
    return ETA(distance - other.distance, time - other.time);
  }
}
