/// When time is -1, there is no solution... (infinite eta)
class ETA {
  /// Meters
  late double distance;
  late Duration? time;

  ETA(this.distance, this.time);
  ETA.fromSpeed(this.distance, double speed) {
    if (speed > 0) {
      time = Duration(milliseconds: distance * 1000 ~/ speed);
    } else {
      time = null;
    }
  }

  ETA operator +(ETA other) {
    final retTime = (time == null || other.time == null) ? null : time! + other.time!;
    return ETA(distance + other.distance, retTime);
  }

  ETA operator -(ETA other) {
    final retTime = (time != null || other.time != null) ? null : time! + other.time!;
    return ETA(distance - other.distance, retTime);
  }
}
