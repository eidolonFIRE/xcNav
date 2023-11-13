import 'package:xcnav/models/geo.dart';

/// When time is -1, there is no solution... (infinite eta)
class ETA {
  /// Meters
  late double distance;
  late Duration? time;
  PathIntercept? pathIntercept;

  ETA(this.distance, this.time, {this.pathIntercept});
  ETA.fromSpeed(this.distance, double speed, {this.pathIntercept}) {
    if (speed > 0.001) {
      time = Duration(milliseconds: distance * 1000 ~/ speed);
    } else {
      time = null;
    }
  }

  /// Meters/Sec
  double? get speed {
    if (time != null) {
      return distance / time!.inMilliseconds * 1000;
    } else {
      return null;
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
