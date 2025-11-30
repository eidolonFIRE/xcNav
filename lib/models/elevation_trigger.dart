import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/altimeter.dart';

enum TriggerDirection {
  up,
  down,
}

class ElevationTrigger {
  late final String name;

  late final AltimeterMode altimeterMode;
  late final double elevation;
  late final TriggerDirection direction;
  late final String? customCallout;
  late final int calloutRepeats;

  late bool enabled;
  bool isTriggered = false;

  ElevationTrigger(
      {required this.name,
      this.enabled = true,
      required this.elevation,
      required this.altimeterMode,
      required this.direction,
      this.customCallout,
      this.calloutRepeats = 1});

  ElevationTrigger.fromJson(Map<String, dynamic> json) {
    name = json["name"];
    enabled = json["enabled"];
    elevation = parseAsDouble(json["elevation"]) ?? 0;
    altimeterMode = AltimeterMode.values[json["mode"]];
    direction = TriggerDirection.values[json["direction"]];
    customCallout = json["customCallout"];
    calloutRepeats = parseAsInt(json["calloutRepeats"]) ?? 1;
  }

  dynamic toJson() {
    return {
      "name": name,
      "enabled": enabled,
      "elevation": elevation,
      "mode": altimeterMode.index,
      "direction": direction.index,
      "customCallout": customCallout,
      "calloutRepeats": calloutRepeats,
    };
  }
}
