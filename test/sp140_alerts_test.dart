import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/ble_devices/ble_device_sp140.dart';
import 'package:xcnav/ble_devices/sp140_alerts.dart';

/// Telemetry with every value in its normal range.
BleFastLinkTelemetry healthy({int uptimeMs = 10000}) {
  final t = BleFastLinkTelemetry()
    ..uptimeMs = uptimeMs
    ..baroPressureDHPa = 10132
    ..baroTempDC = 200
    ..mcuTempDC = 400
    ..escStatus = sp140TelemetryConnected
    ..escTempMosDC = 300
    ..escTempCapDC = 300
    ..escTempMcuDC = 300
    ..escTempMotorDC = 300
    ..bmsStatus = sp140TelemetryConnected
    ..bmsSoc = 80
    ..bmsVoltsDV = 950
    ..bmsIsDischargeMos = 1
    ..bmsCellMaxMV = 3960
    ..bmsCellMinMV = 3950
    ..bmsVoltageDiffMV = 10;
  t.bmsTempSensorsC.fillRange(0, 6, 25);
  return t;
}

/// Monitor past the BMS grace period.
Sp140AlertMonitor armed() => Sp140AlertMonitor()..update(healthy(uptimeMs: 0));

List<String> codes(List<Sp140Alert> alerts) => alerts.map((e) => e.code).toList();

void main() {
  group("Sp140AlertMonitor", () {
    test("healthy telemetry has no alerts", () {
      expect(Sp140AlertMonitor().update(healthy()), isEmpty);
    });

    test("ESC temperature levels", () {
      final monitor = Sp140AlertMonitor();
      expect(monitor.update(healthy()..escTempMosDC = 900),
          [const Sp140Alert("MC-F", "ESC MOSFET temp high", Sp140AlertLevel.warning)]);
      expect(monitor.update(healthy()..escTempMosDC = 1100),
          [const Sp140Alert("MC-F", "ESC MOSFET temp high", Sp140AlertLevel.critical)]);
      expect(Sp140AlertMonitor().update(healthy()..escTempMosDC = -250).single.name, "ESC MOSFET temp low");
    });

    test("temperature hysteresis", () {
      final monitor = Sp140AlertMonitor();
      expect(codes(monitor.update(healthy()..escTempMcuDC = 800)), ["MC-C"]);
      // Inside the 1C band: still warning
      expect(codes(monitor.update(healthy()..escTempMcuDC = 795)), ["MC-C"]);
      expect(monitor.update(healthy()..escTempMcuDC = 789), isEmpty);

      expect(monitor.update(healthy()..escTempMcuDC = 950).single.level, Sp140AlertLevel.critical);
      expect(monitor.update(healthy()..escTempMcuDC = 945).single.level, Sp140AlertLevel.critical);
      expect(monitor.update(healthy()..escTempMcuDC = 930).single.level, Sp140AlertLevel.warning);
    });

    test("missing motor temp sensor is ignored", () {
      expect(Sp140AlertMonitor().update(healthy()..escTempMotorDC = sp140NoTempSensorDC), isEmpty);
    });

    test("ESC error bits", () {
      final alerts = Sp140AlertMonitor().update(healthy()
        ..escError = (1 << 0) | (1 << 5) | (1 << 7)
        ..escSelfcheck = (1 << 13) | (1 << 12));
      // Throttle saturation (bit 5) and undefined self-check bit 12 aren't alerts.
      expect(codes(alerts), ["MC-RE-0", "MC-RE-7", "MC-SE-13"]);
      expect(alerts.every((e) => e.isCritical), isTrue);
    });

    test("BMS voltage and charge alerts", () {
      final monitor = armed();
      expect(monitor.update(healthy()..bmsSoc = 15).single,
          const Sp140Alert("BC-SOC", "Battery charge low", Sp140AlertLevel.warning));
      expect(monitor.update(healthy()..bmsSoc = 5).single.level, Sp140AlertLevel.critical);

      expect(codes(monitor.update(healthy()..bmsCellMaxMV = 4190)), ["BC-CV-H"]);
      expect(monitor.update(healthy()..bmsCellMaxMV = 4200).single.level, Sp140AlertLevel.critical);
      expect(codes(monitor.update(healthy()..bmsCellMinMV = 3100)), ["BC-CV-L"]);
      expect(monitor.update(healthy()..bmsCellMinMV = 3000).single.level, Sp140AlertLevel.critical);

      expect(monitor.update(healthy()..bmsVoltsDV = 790).single.name, "Battery voltage low");
      expect(monitor.update(healthy()..bmsVoltsDV = 1010).single.level, Sp140AlertLevel.critical);

      expect(monitor.update(healthy()..bmsVoltageDiffMV = 199), isEmpty);
      expect(monitor.update(healthy()..bmsVoltageDiffMV = 200).single.level, Sp140AlertLevel.warning);
      expect(monitor.update(healthy()..bmsVoltageDiffMV = 400).single.level, Sp140AlertLevel.critical);
    });

    test("BMS temperature sensors", () {
      final t = healthy();
      t.bmsTempSensorsC[1] = 50;
      t.bmsTempSensorsC[5] = 56;
      final alerts = armed().update(t);
      expect(codes(alerts), ["BC-T4", "BC-B"]);
      expect(alerts.first.isCritical, isTrue);
    });

    test("discharge MOSFET off", () {
      expect(codes(armed().update(healthy()..bmsIsDischargeMos = 0)), ["BC-DSG"]);
    });

    test("BMS without data yet is ignored", () {
      final t = healthy()
        ..bmsVoltsDV = 0
        ..bmsSoc = 0
        ..bmsIsDischargeMos = 0
        ..bmsCellMinMV = 0;
      expect(armed().update(t), isEmpty);
    });

    test("disconnected NaN BMS temp probes are ignored", () {
      final t = healthy();
      t.bmsTempSensorsC[2] = 127;
      t.bmsTempSensorsC[3] = -128;
      expect(armed().update(t), isEmpty);
      // Too many disconnected probes: the controller sends -40C on purpose.
      t.bmsTempSensorsC[4] = -40;
      expect(codes(armed().update(t)), ["BC-T3"]);
    });

    test("BMS grace period after first connect", () {
      final monitor = Sp140AlertMonitor();
      BleFastLinkTelemetry low(int uptimeMs) => healthy(uptimeMs: uptimeMs)..bmsSoc = 3;
      expect(monitor.update(healthy(uptimeMs: 500)..bmsStatus = 0), isEmpty);
      expect(monitor.update(low(1000)), isEmpty);
      expect(monitor.update(low(2999)), isEmpty);
      expect(codes(monitor.update(low(3000))), ["BC-SOC"]);

      // A link drop clears alerts but doesn't restart the grace period.
      expect(monitor.update(low(4000)..bmsStatus = 0), isEmpty);
      expect(codes(monitor.update(low(4100))), ["BC-SOC"]);

      // A controller reboot does.
      expect(monitor.update(low(500)), isEmpty);
      expect(codes(monitor.update(low(2500))), ["BC-SOC"]);
    });

    test("lost ESC or BMS link is silent", () {
      final monitor = armed();
      BleFastLinkTelemetry lost(int uptimeMs) => healthy(uptimeMs: uptimeMs)
        ..escStatus = 0
        ..bmsStatus = 0
        // Stale out of range values must not alert while disconnected.
        ..escTempMosDC = 2000
        ..bmsSoc = 0;
      expect(monitor.update(lost(1000)), isEmpty);
      expect(monitor.update(lost(60000)), isEmpty);
    });

    test("CPU temp", () {
      final monitor = Sp140AlertMonitor();
      expect(codes(monitor.update(healthy()..mcuTempDC = 600)), ["CPU-T"]);
      // Unread sensor holds the last level.
      expect(codes(monitor.update(healthy()..mcuTempDC = 0)), ["CPU-T"]);
      expect(monitor.update(healthy()), isEmpty);
      expect(monitor.update(healthy()..mcuTempDC = 0), isEmpty);
      expect(monitor.update(healthy()..mcuTempDC = 32767), isEmpty);
    });

    test("barometer temp", () {
      final monitor = Sp140AlertMonitor();
      expect(monitor.update(healthy()..baroTempDC = 0), isEmpty);
      expect(monitor.update(healthy()..baroTempDC = -5).single,
          const Sp140Alert("BARO-T", "Barometer temp low", Sp140AlertLevel.warning));
      // Failed read holds the last level.
      expect(codes(monitor.update(healthy()..baroTempDC = 0)), ["BARO-T"]);
      expect(monitor.update(healthy()..baroTempDC = 800).single.level, Sp140AlertLevel.critical);
    });

    test("barometer failure needs zero pressure since boot", () {
      final monitor = Sp140AlertMonitor();
      BleFastLinkTelemetry noBaro(int uptimeMs) => healthy(uptimeMs: uptimeMs)
        ..baroPressureDHPa = 0
        ..baroTempDC = 0;
      expect(monitor.update(noBaro(100)), isEmpty);
      expect(monitor.update(noBaro(1099)), isEmpty);
      expect(codes(monitor.update(noBaro(1100))), ["BARO-I"]);

      // Once the barometer worked, a zero read is a busy bus.
      final working = Sp140AlertMonitor()..update(healthy(uptimeMs: 100));
      expect(working.update(noBaro(200)), isEmpty);
      expect(working.update(noBaro(5000)), isEmpty);

      // Until the controller reboots.
      expect(working.update(noBaro(100)), isEmpty);
      expect(codes(working.update(noBaro(1100))), ["BARO-I"]);
    });

    test("critical alerts sort first", () {
      final alerts = armed().update(healthy()
        ..bmsSoc = 10
        ..escError = 1 << 1);
      expect(codes(alerts), ["MC-RE-1", "BC-SOC"]);
    });
  });

  group("Sp140AlertAnnouncer", () {
    const warn = Sp140Alert("BC-dV", "Battery imbalance high", Sp140AlertLevel.warning);
    const crit = Sp140Alert("BC-dV", "Battery imbalance high", Sp140AlertLevel.critical);
    final t0 = DateTime(2026, 1, 1);

    test("speaks new, escalated, and repeated alerts", () {
      final announcer = Sp140AlertAnnouncer();
      expect(announcer.due([warn], t0), [warn]);
      expect(announcer.due([warn], t0.add(const Duration(seconds: 1))), isEmpty);
      // Cleared then raised again doesn't repeat right away.
      expect(announcer.due([], t0.add(const Duration(seconds: 2))), isEmpty);
      expect(announcer.due([warn], t0.add(const Duration(seconds: 3))), isEmpty);
      expect(announcer.due([crit], t0.add(const Duration(seconds: 4))), [crit]);
      // De-escalating is silent.
      expect(announcer.due([warn], t0.add(const Duration(seconds: 5))), isEmpty);
      expect(announcer.due([warn], t0.add(const Duration(minutes: 2, seconds: 4))), [warn]);
    });

    test("messages", () {
      const other = Sp140Alert("MC-RE-0", "ESC over current", Sp140AlertLevel.critical);
      final messages = Sp140AlertAnnouncer.messages([other, crit, warn]);
      expect(messages.map((e) => e.text),
          ["Critical! ESC over current, Battery imbalance high!", "Check Battery imbalance high!"]);
      expect(messages.map((e) => e.priority), [1, 2]);
      expect(Sp140AlertAnnouncer.messages([]), isEmpty);
    });

    test("messages muted by level", () {
      expect(Sp140AlertAnnouncer.messages([crit, warn], warnings: false).map((e) => e.text),
          ["Critical! Battery imbalance high!"]);
      expect(Sp140AlertAnnouncer.messages([crit, warn], critical: false).map((e) => e.text),
          ["Check Battery imbalance high!"]);
      expect(Sp140AlertAnnouncer.messages([crit, warn], warnings: false, critical: false), isEmpty);
    });
  });
}
