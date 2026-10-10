/// Tunable thresholds for automatic launch (takeoff) detection.
class LaunchDetectorConfig {
  /// Meters/sec
  final double minSpeed;

  /// Meters/sec
  final double maxSpeed;

  final bool useAgl;

  /// Meters above ground
  final double minAgl;

  final bool useVario;

  /// Meters/sec of climb
  final double minVario;

  /// How long the conditions must hold before launch is declared.
  final Duration holdTime;

  /// Declare launch immediately when the SP140 is armed.
  final bool useSp140Armed;

  const LaunchDetectorConfig({
    this.minSpeed = 4.0,
    this.maxSpeed = 25,
    this.useAgl = true,
    this.minAgl = 30,
    this.useVario = true,
    this.minVario = 1.4,
    this.holdTime = const Duration(seconds: 15),
    this.useSp140Armed = true,
  });

  /// Is the current sample consistent with being in flight?
  ///
  /// `agl` is null when ground elevation is unavailable, in which case the AGL check passes.
  bool isLaunchCandidate({required double speed, required double? agl, required double vario}) {
    if (speed <= minSpeed || speed >= maxSpeed) return false;
    if (!useAgl && !useVario) return true;
    final aglOk = useAgl && (agl == null || agl > minAgl);
    final varioOk = useVario && vario > minVario;
    return aglOk || varioOk;
  }

  /// Should launch be declared, given accumulated hysteresis (ms) and SP140 armed state?
  bool shouldLaunch({required int triggerHystMs, required bool? sp140Armed}) {
    return triggerHystMs > holdTime.inMilliseconds || (useSp140Armed && sp140Armed == true);
  }
}

/// Tunable thresholds for automatic landing detection.
class LandingDetectorConfig {
  /// Meters/sec
  final double maxSpeed;

  final bool useVario;

  /// Meters/sec of climb or sink
  final double maxVario;

  final bool useAgl;

  /// Meters above ground
  final double maxAgl;

  /// How long the conditions must hold before landing is declared.
  final Duration holdTime;

  /// Never declare landing while the SP140 is armed.
  final bool useSp140Armed;

  const LandingDetectorConfig({
    this.maxSpeed = 1.7,
    this.useVario = true,
    this.maxVario = 0.3,
    this.useAgl = true,
    this.maxAgl = 100,
    this.holdTime = const Duration(seconds: 20),
    this.useSp140Armed = true,
  });

  /// Is the current sample consistent with being on the ground?
  ///
  /// `agl` is null when ground elevation is unavailable, in which case the AGL check passes.
  bool isLandingCandidate({required double speed, required double? agl, required double vario}) {
    if (speed >= maxSpeed) return false;
    if (useVario && vario.abs() >= maxVario) return false;
    if (useAgl && agl != null && agl >= maxAgl) return false;
    return true;
  }

  /// Should landing be declared, given accumulated hysteresis (ms) and SP140 armed state?
  bool shouldLand({required int triggerHystMs, required bool? sp140Armed}) {
    return triggerHystMs > holdTime.inMilliseconds && !(useSp140Armed && sp140Armed == true);
  }
}
