import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

class CarbNeedle with ChangeNotifier {
  double _mixture = 0;
  int _servoPWM = 0;

  bool pointerDown = false;

  /// Current Needle Setting 0-1
  ///
  /// 0.0 = rich,
  /// 1.0 = lean
  double get mixture => _mixture;
  set mixture(double value) {
    _mixture = max(0, min(1, value));
    _servoPWM = round(servoEndstops.first * (1.0 - _mixture) + servoEndstops.last * _mixture).toInt();
    // debugPrint("servo pwm: $_servoPWM");
    notifyListeners();
  }

  /// Current PWM setting (configured by endstops)
  int get servoPWM => _servoPWM;

  // config

  /// Degrees of freedom
  final double dof;
  final List<int> servoEndstops;
  final String uuid;

  late Map<String, double> presets;

  CarbNeedle({required this.uuid, this.dof = pi, this.servoEndstops = const [104, 494]}) {
    presets = {"Factory": 0.2, "Cruise": 0.5, "Eco": 0.8};
  }
}
