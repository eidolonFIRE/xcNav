import 'package:xcnav/ble_devices/ble_device_sp140.dart';
import 'package:xcnav/tts_service.dart';

// Mirrors the SP140 hand controller's own alert monitors.
// Docs: https://docs.openppg.com/docs/sp140-manual/alerts/
// Thresholds: openppg/eppg-controller inc/sp140/monitor_config.h

enum Sp140AlertLevel { warning, critical }

class Sp140Alert {
  /// Code shown on the SP140 display (e.g. "MC-F")
  final String code;

  /// Human readable (and spoken) description
  final String name;
  final Sp140AlertLevel level;

  const Sp140Alert(this.code, this.name, this.level);

  bool get isCritical => level == Sp140AlertLevel.critical;

  @override
  bool operator ==(Object other) =>
      other is Sp140Alert && other.code == code && other.name == name && other.level == level;

  @override
  int get hashCode => Object.hash(code, name, level);

  @override
  String toString() => "$code ($name, ${level.name})";
}

enum _Level { ok, warnLow, warnHigh, critLow, critHigh }

/// Thresholds are in the native units of the telemetry field they check.
/// Matching the firmware, limits are inclusive.
class Sp140Thresholds {
  final num warnLow;
  final num warnHigh;
  final num critLow;
  final num critHigh;
  final num hysteresis;

  const Sp140Thresholds(
      {this.warnLow = double.negativeInfinity,
      this.warnHigh = double.infinity,
      this.critLow = double.negativeInfinity,
      this.critHigh = double.infinity,
      this.hysteresis = 0});
}

class _ThresholdMonitor {
  final Sp140Thresholds thr;
  _Level last = _Level.ok;

  _ThresholdMonitor(this.thr);

  _Level _evaluate(num v) {
    if (v <= thr.critLow) return _Level.critLow;
    if (v <= thr.warnLow) return _Level.warnLow;
    if (v >= thr.critHigh) return _Level.critHigh;
    if (v >= thr.warnHigh) return _Level.warnHigh;
    return _Level.ok;
  }

  /// Same state machine as the firmware's HysteresisSensorMonitor:
  /// escalate at the exact threshold, de-escalate only past the hysteresis band.
  /// Without hysteresis it's the plain SensorMonitor.
  _Level check(num? v) {
    if (v == null) return last = _Level.ok;
    if (thr.hysteresis == 0) return last = _evaluate(v);

    final h = thr.hysteresis;
    switch (last) {
      case _Level.ok:
        last = _evaluate(v);
      case _Level.warnLow:
        if (v <= thr.critLow) {
          last = _Level.critLow;
        } else if (v > thr.warnLow + h) {
          last = _Level.ok;
        }
      case _Level.warnHigh:
        if (v >= thr.critHigh) {
          last = _Level.critHigh;
        } else if (v < thr.warnHigh - h) {
          last = _Level.ok;
        }
      case _Level.critLow:
        if (v > thr.critLow + h) {
          last = v <= thr.warnLow + h ? _Level.warnLow : _Level.ok;
        }
      case _Level.critHigh:
        if (v < thr.critHigh - h) {
          last = v >= thr.warnHigh - h ? _Level.warnHigh : _Level.ok;
        }
    }
    return last;
  }

  void reset() => last = _Level.ok;
}

class _ThresholdAlert {
  final String code;
  final String name;
  final _ThresholdMonitor monitor;

  /// Returns null when the sensor has no valid reading, which clears the alert (firmware NaN).
  final num? Function(BleFastLinkTelemetry t) read;

  /// True when the packet carries no fresh reading, so the previous level holds.
  /// The firmware monitors a cached value that a failed read doesn't overwrite.
  final bool Function(BleFastLinkTelemetry t)? stale;

  _ThresholdAlert(this.code, this.name, Sp140Thresholds thr, this.read, {this.stale})
      : monitor = _ThresholdMonitor(thr);

  Sp140Alert? check(BleFastLinkTelemetry t) {
    final level = (stale?.call(t) ?? false) ? monitor.last : monitor.check(read(t));
    switch (level) {
      case _Level.ok:
        return null;
      case _Level.warnLow:
        return Sp140Alert(code, "$name low", Sp140AlertLevel.warning);
      case _Level.warnHigh:
        return Sp140Alert(code, "$name high", Sp140AlertLevel.warning);
      case _Level.critLow:
        return Sp140Alert(code, "$name low", Sp140AlertLevel.critical);
      case _Level.critHigh:
        return Sp140Alert(code, "$name high", Sp140AlertLevel.critical);
    }
  }
}

/// Telemetry status values (TelemetryState enum in firmware)
const int sp140TelemetryConnected = 1;

/// Sentinel the firmware sends when the motor temp sensor is missing.
const int sp140NoTempSensorDC = -32768;

/// BMS monitors stay off this long after the BMS first connects (firmware BMS_ALERT_GRACE_MS).
const int sp140BmsAlertGraceMs = 2000;

/// Pack voltage at or below this means the BMS hasn't sent data yet (firmware bmsDataValid).
const int sp140BmsMinValidDV = 50;

/// How long pressure must read zero before reporting a barometer failure.
/// A busy I2C bus also reads zero for a single sample.
const int sp140BaroFailMs = 1000;

/// The firmware converts a NaN reading to the integer limits of the field.
num? _validI8(int v) => (v == -128 || v == 127) ? null : v;
num? _validI16(int v) => (v == -32768 || v == 32767) ? null : v;

/// ESC running error bits (all critical)
const Map<int, String> sp140EscRunningErrors = {
  0: "ESC over current",
  1: "ESC locked rotor",
  2: "ESC over temperature",
  6: "ESC over voltage",
  7: "ESC voltage drop",
};

/// ESC self-check error bits (all critical)
const Map<int, String> sp140EscSelfCheckErrors = {
  0: "ESC motor current sensor fault",
  1: "ESC total current sensor fault",
  2: "ESC motor voltage sensor fault",
  3: "ESC capacitor temp sensor fault",
  4: "ESC MOSFET temp sensor fault",
  5: "ESC bus voltage out of range",
  6: "ESC bus voltage sampling fault",
  7: "Motor impedance too low",
  8: "Motor impedance too high",
  9: "ESC motor voltage detect 1 fault",
  10: "ESC motor voltage detect 2 fault",
  11: "ESC motor current detect 2 fault",
  13: "ESC firmware mismatch",
  14: "ESC bootloader unsupported",
};

/// Evaluates SP140 FastLink telemetry against the hand controller's alert monitors.
///
/// Stateful: temperature alerts use hysteresis, and some checks wait out the controller's boot.
/// A lost ESC or BMS link isn't an alert: the controller just clears that device's alerts.
class Sp140AlertMonitor {
  // --- ESC (deci-C)
  final _esc = [
    _ThresholdAlert(
        "MC-F",
        "ESC MOSFET temp",
        const Sp140Thresholds(warnLow: -100, warnHigh: 900, critLow: -200, critHigh: 1100, hysteresis: 10),
        (t) => t.escTempMosDC),
    _ThresholdAlert(
        "MC-C",
        "ESC controller temp",
        const Sp140Thresholds(warnLow: -100, warnHigh: 800, critLow: -200, critHigh: 950, hysteresis: 10),
        (t) => t.escTempMcuDC),
    _ThresholdAlert(
        "MC-P",
        "ESC capacitor temp",
        const Sp140Thresholds(warnLow: -100, warnHigh: 850, critLow: -200, critHigh: 1000, hysteresis: 10),
        (t) => t.escTempCapDC),
    _ThresholdAlert(
        "MC-M",
        "Motor temp",
        const Sp140Thresholds(warnLow: -200, warnHigh: 1050, critLow: -250, critHigh: 1150, hysteresis: 10),
        (t) => _validI16(t.escTempMotorDC)),
  ];

  // --- BMS
  static const _bmsTemp = Sp140Thresholds(warnLow: -10, warnHigh: 50, critLow: -15, critHigh: 60, hysteresis: 1);
  static const _bmsCellTemp = Sp140Thresholds(warnLow: -10, warnHigh: 50, critLow: -15, critHigh: 56, hysteresis: 1);

  static bool _bmsDataValid(BleFastLinkTelemetry t) => t.bmsVoltsDV > sp140BmsMinValidDV;

  final _bms = [
    // Temperatures (C). Sensor order: MOS, BAL, T1-T4. A disconnected probe reads NaN.
    _ThresholdAlert("BC-F", "Battery MOSFET temp", _bmsTemp, (t) => _validI8(t.bmsTempSensorsC[0])),
    _ThresholdAlert("BC-B", "Battery balance resistor temp", _bmsTemp, (t) => _validI8(t.bmsTempSensorsC[1])),
    _ThresholdAlert("BC-T1", "Battery cell group 1 temp", _bmsCellTemp, (t) => _validI8(t.bmsTempSensorsC[2])),
    _ThresholdAlert("BC-T2", "Battery cell group 2 temp", _bmsCellTemp, (t) => _validI8(t.bmsTempSensorsC[3])),
    _ThresholdAlert("BC-T3", "Battery cell group 3 temp", _bmsCellTemp, (t) => _validI8(t.bmsTempSensorsC[4])),
    _ThresholdAlert("BC-T4", "Battery cell group 4 temp", _bmsCellTemp, (t) => _validI8(t.bmsTempSensorsC[5])),
    // Voltages (mV / deci-V). Skipped until the pack voltage arrives.
    _ThresholdAlert("BC-CV-H", "Cell voltage", const Sp140Thresholds(warnHigh: 4190, critHigh: 4200),
        (t) => _bmsDataValid(t) ? t.bmsCellMaxMV : null),
    _ThresholdAlert("BC-CV-L", "Cell voltage", const Sp140Thresholds(warnLow: 3200, critLow: 3000),
        (t) => _bmsDataValid(t) ? t.bmsCellMinMV : null),
    _ThresholdAlert("BC-SOC", "Battery charge", const Sp140Thresholds(warnLow: 15, critLow: 5),
        (t) => _bmsDataValid(t) ? t.bmsSoc : null),
    _ThresholdAlert("BC-Vtot", "Battery voltage",
        const Sp140Thresholds(warnLow: 792, warnHigh: 1004, critLow: 696, critHigh: 1008),
        (t) => _bmsDataValid(t) ? t.bmsVoltsDV : null),
    _ThresholdAlert("BC-dV", "Battery imbalance", const Sp140Thresholds(warnHigh: 200, critHigh: 400),
        (t) => _bmsDataValid(t) ? t.bmsVoltageDiffMV : null),
  ];

  // --- Internal (deci-C)
  // Zero means the controller hasn't read the sensor (yet), not 0.0C.
  final _cpuTemp = _ThresholdAlert(
      "CPU-T",
      "Controller CPU temp",
      const Sp140Thresholds(warnLow: 0, warnHigh: 600, critLow: -100, critHigh: 800, hysteresis: 10),
      (t) => _validI16(t.mcuTempDC),
      stale: (t) => t.mcuTempDC == 0);
  final _baroTemp = _ThresholdAlert("BARO-T", "Barometer temp",
      const Sp140Thresholds(warnLow: 0, warnHigh: 500, critLow: -100, critHigh: 800), (t) => t.baroTempDC,
      stale: (t) => t.baroTempDC == 0);

  int? _lastUptimeMs;
  int? _bmsConnectedAtMs;
  bool _baroSeen = false;
  int? _baroZeroSinceMs;

  /// Returns the active alerts, critical first.
  List<Sp140Alert> update(BleFastLinkTelemetry t) {
    final alerts = <Sp140Alert>[];

    // Controller rebooted (uptime went backwards), so its once-per-boot state restarts.
    if (_lastUptimeMs != null && t.uptimeMs < _lastUptimeMs!) {
      _bmsConnectedAtMs = null;
      _baroSeen = false;
      _baroZeroSinceMs = null;
    }
    _lastUptimeMs = t.uptimeMs;

    // --- ESC
    if (t.escStatus == sp140TelemetryConnected) {
      for (final each in _esc) {
        final alert = each.check(t);
        if (alert != null) alerts.add(alert);
      }
      sp140EscRunningErrors.forEach((bit, name) {
        if (t.escError & (1 << bit) != 0) alerts.add(Sp140Alert("MC-RE-$bit", name, Sp140AlertLevel.critical));
      });
      sp140EscSelfCheckErrors.forEach((bit, name) {
        if (t.escSelfcheck & (1 << bit) != 0) alerts.add(Sp140Alert("MC-SE-$bit", name, Sp140AlertLevel.critical));
      });
    } else {
      for (final each in _esc) {
        each.monitor.reset();
      }
    }

    // --- BMS
    // A booting BMS can send garbage, so hold off after it first connects.
    // Only once per controller boot: a link drop mid-flight must not mute alerts again.
    final bmsConnected = t.bmsStatus == sp140TelemetryConnected;
    if (bmsConnected) _bmsConnectedAtMs ??= t.uptimeMs;
    if (bmsConnected && t.uptimeMs - _bmsConnectedAtMs! >= sp140BmsAlertGraceMs) {
      for (final each in _bms) {
        final alert = each.check(t);
        if (alert != null) alerts.add(alert);
      }
      if (_bmsDataValid(t) && t.bmsIsDischargeMos == 0) {
        alerts.add(const Sp140Alert("BC-DSG", "Battery discharge disabled", Sp140AlertLevel.critical));
      }
    } else {
      for (final each in _bms) {
        each.monitor.reset();
      }
    }

    // --- Altimeter
    // The controller only flags the barometer when it fails to start at boot.
    // Pressure reads zero then, but also for a single sample when the I2C bus is busy.
    if (t.baroPressureDHPa != 0) {
      _baroSeen = true;
      _baroZeroSinceMs = null;
    } else if (!_baroSeen) {
      _baroZeroSinceMs ??= t.uptimeMs;
      if (t.uptimeMs - _baroZeroSinceMs! >= sp140BaroFailMs) {
        alerts.add(const Sp140Alert("BARO-I", "Barometer failed", Sp140AlertLevel.warning));
      }
    }
    final baroTemp = _baroTemp.check(t);
    if (baroTemp != null) alerts.add(baroTemp);

    // --- Internal
    final cpu = _cpuTemp.check(t);
    if (cpu != null) alerts.add(cpu);

    return [...alerts.where((e) => e.isCritical), ...alerts.where((e) => !e.isCritical)];
  }
}

/// Decides which alerts to speak, so a value hovering at a threshold doesn't repeat endlessly.
class Sp140AlertAnnouncer {
  static const repeatInterval = Duration(minutes: 2);

  final _announced = <String, ({Sp140AlertLevel level, DateTime time})>{};

  /// Alerts that are new, escalated to critical, or haven't been spoken within [repeatInterval].
  List<Sp140Alert> due(List<Sp140Alert> alerts, DateTime now) {
    final result = <Sp140Alert>[];
    for (final alert in alerts) {
      final last = _announced[alert.code];
      if (last == null || alert.level.index > last.level.index || !last.time.isAfter(now.subtract(repeatInterval))) {
        _announced[alert.code] = (level: alert.level, time: now);
        result.add(alert);
      }
    }
    return result;
  }

  /// Spoken messages for [alerts], critical first. Levels that are turned off stay silent.
  static List<AudioMessage> messages(List<Sp140Alert> alerts, {bool warnings = true, bool critical = true}) {
    final criticalNames = alerts.where((e) => critical && e.isCritical).map((e) => e.name);
    final warningNames = alerts.where((e) => warnings && !e.isCritical).map((e) => e.name);
    return [
      if (criticalNames.isNotEmpty) AudioMessage("Critical! ${criticalNames.join(", ")}!", priority: 1, volume: 1.0),
      if (warningNames.isNotEmpty) AudioMessage("Check ${warningNames.join(", ")}!", priority: 2, volume: 1.0),
    ];
  }
}
