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

  /// Returns null when the sensor has no valid reading.
  final num? Function(BleFastLinkTelemetry t) read;

  _ThresholdAlert(this.code, this.name, Sp140Thresholds thr, this.read) : monitor = _ThresholdMonitor(thr);

  Sp140Alert? check(BleFastLinkTelemetry t) {
    final level = monitor.check(read(t));
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

/// How long the ESC or BMS link must be down before raising a CAN alert.
/// Avoids alerting while the controller is still booting.
const int sp140CanAlertDelayMs = 5000;

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

/// Evaluates SP140 FastLink telemetry against the hand controller's alert thresholds.
///
/// Stateful: temperature alerts use hysteresis, and CAN alerts need a sustained link loss.
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
        (t) => t.escTempMotorDC == sp140NoTempSensorDC ? null : t.escTempMotorDC),
  ];

  // --- BMS
  static const _bmsTemp = Sp140Thresholds(warnLow: -10, warnHigh: 50, critLow: -15, critHigh: 60, hysteresis: 1);
  static const _bmsCellTemp = Sp140Thresholds(warnLow: -10, warnHigh: 50, critLow: -15, critHigh: 56, hysteresis: 1);
  final _bms = [
    // Temperatures (C). Sensor order: MOS, BAL, T1-T4
    _ThresholdAlert("BC-F", "Battery MOSFET temp", _bmsTemp, (t) => t.bmsTempSensorsC[0]),
    _ThresholdAlert("BC-B", "Battery balance resistor temp", _bmsTemp, (t) => t.bmsTempSensorsC[1]),
    _ThresholdAlert("BC-T1", "Battery cell group 1 temp", _bmsCellTemp, (t) => t.bmsTempSensorsC[2]),
    _ThresholdAlert("BC-T2", "Battery cell group 2 temp", _bmsCellTemp, (t) => t.bmsTempSensorsC[3]),
    _ThresholdAlert("BC-T3", "Battery cell group 3 temp", _bmsCellTemp, (t) => t.bmsTempSensorsC[4]),
    _ThresholdAlert("BC-T4", "Battery cell group 4 temp", _bmsCellTemp, (t) => t.bmsTempSensorsC[5]),
    // Voltages (mV / deci-V)
    _ThresholdAlert(
        "BC-CV-H", "Cell voltage", const Sp140Thresholds(warnHigh: 4190, critHigh: 4200), (t) => t.bmsCellMaxMV),
    _ThresholdAlert(
        "BC-CV-L", "Cell voltage", const Sp140Thresholds(warnLow: 3200, critLow: 3000), (t) => t.bmsCellMinMV),
    _ThresholdAlert("BC-SOC", "Battery charge", const Sp140Thresholds(warnLow: 15, critLow: 5), (t) => t.bmsSoc),
    _ThresholdAlert("BC-Vtot", "Battery voltage",
        const Sp140Thresholds(warnLow: 792, warnHigh: 1004, critLow: 696, critHigh: 1008), (t) => t.bmsVoltsDV),
    _ThresholdAlert(
        "BC-dV", "Battery imbalance", const Sp140Thresholds(warnHigh: 200, critHigh: 400), (t) => t.bmsVoltageDiffMV),
  ];

  // --- Internal (deci-C)
  final _cpuTemp = _ThresholdAlert(
      "CPU-T",
      "Controller CPU temp",
      const Sp140Thresholds(warnLow: 0, warnHigh: 600, critLow: -100, critHigh: 800, hysteresis: 10),
      (t) => t.mcuTempDC);

  int? _escLostAtMs;
  int? _bmsLostAtMs;

  /// Returns the active alerts, critical first.
  List<Sp140Alert> update(BleFastLinkTelemetry t) {
    final alerts = <Sp140Alert>[];

    // --- ESC
    if (t.escStatus == sp140TelemetryConnected) {
      _escLostAtMs = null;
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
      _escLostAtMs = _lostSince(_escLostAtMs, t.uptimeMs);
      if (t.uptimeMs - _escLostAtMs! >= sp140CanAlertDelayMs) {
        alerts.add(const Sp140Alert("MC-CAN", "ESC not connected", Sp140AlertLevel.warning));
      }
    }

    // --- BMS
    // A freshly connected BMS reports zeros until its first data frames arrive.
    if (t.bmsStatus == sp140TelemetryConnected && t.bmsVoltsDV > 50) {
      _bmsLostAtMs = null;
      for (final each in _bms) {
        final alert = each.check(t);
        if (alert != null) alerts.add(alert);
      }
      if (t.bmsIsDischargeMos == 0) {
        alerts.add(const Sp140Alert("BC-DSG", "Battery discharge disabled", Sp140AlertLevel.critical));
      }
    } else {
      for (final each in _bms) {
        each.monitor.reset();
      }
      if (t.bmsStatus != sp140TelemetryConnected) {
        _bmsLostAtMs = _lostSince(_bmsLostAtMs, t.uptimeMs);
        if (t.uptimeMs - _bmsLostAtMs! >= sp140CanAlertDelayMs) {
          alerts.add(const Sp140Alert("BC-CAN", "Battery not connected", Sp140AlertLevel.warning));
        }
      }
    }

    // --- Internal
    final cpu = _cpuTemp.check(t);
    if (cpu != null) alerts.add(cpu);
    // Pressure reads zero when the barometer failed to initialize.
    if (t.baroPressureDHPa == 0) {
      alerts.add(const Sp140Alert("Baro-I", "Barometer failed", Sp140AlertLevel.warning));
    }

    return [...alerts.where((e) => e.isCritical), ...alerts.where((e) => !e.isCritical)];
  }

  /// Restart the timer if the controller rebooted (uptime went backwards).
  static int _lostSince(int? lostAtMs, int uptimeMs) => (lostAtMs == null || uptimeMs < lostAtMs) ? uptimeMs : lostAtMs;
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

  /// Spoken messages for [alerts], critical first.
  static List<AudioMessage> messages(List<Sp140Alert> alerts) {
    final critical = alerts.where((e) => e.isCritical).map((e) => e.name);
    final warnings = alerts.where((e) => !e.isCritical).map((e) => e.name);
    return [
      if (critical.isNotEmpty) AudioMessage("Critical! ${critical.join(", ")}!", priority: 1, volume: 1.0),
      if (warnings.isNotEmpty) AudioMessage("Check ${warnings.join(", ")}!", priority: 2, volume: 1.0),
    ];
  }
}
