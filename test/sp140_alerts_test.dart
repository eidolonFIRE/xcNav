import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/ble_devices/ble_device_sp140.dart';
import 'package:xcnav/ble_devices/sp140_alerts.dart';

/// Telemetry with every value in its normal range.
BleFastLinkTelemetry healthy({int uptimeMs = 10000}) {
  final t = BleFastLinkTelemetry()
    ..uptimeMs = uptimeMs
    ..baroPressureDHPa = 10132
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
      final monitor = Sp140AlertMonitor();
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
      final alerts = Sp140AlertMonitor().update(t);
      expect(codes(alerts), ["BC-T4", "BC-B"]);
      expect(alerts.first.isCritical, isTrue);
    });

    test("discharge MOSFET off", () {
      expect(codes(Sp140AlertMonitor().update(healthy()..bmsIsDischargeMos = 0)), ["BC-DSG"]);
    });

    test("BMS without data yet is ignored", () {
      final t = healthy()
        ..bmsVoltsDV = 0
        ..bmsSoc = 0
        ..bmsIsDischargeMos = 0
        ..bmsCellMinMV = 0;
      expect(Sp140AlertMonitor().update(t), isEmpty);
    });

    test("CAN alerts need sustained link loss", () {
      final monitor = Sp140AlertMonitor();
      BleFastLinkTelemetry lost(int uptimeMs) => healthy(uptimeMs: uptimeMs)
        ..escStatus = 0
        ..bmsStatus = 0
        // Stale out of range values must not alert while disconnected.
        ..escTempMosDC = 2000
        ..bmsSoc = 0;
      expect(monitor.update(lost(1000)), isEmpty);
      expect(monitor.update(lost(5999)), isEmpty);
      expect(codes(monitor.update(lost(6000))), ["MC-CAN", "BC-CAN"]);

      // Reconnect clears, and the delay restarts on the next loss.
      expect(monitor.update(healthy(uptimeMs: 7000)), isEmpty);
      expect(monitor.update(lost(8000)), isEmpty);

      // Controller reboot restarts the delay too.
      expect(monitor.update(lost(500)), isEmpty);
      expect(codes(monitor.update(lost(5500))), ["MC-CAN", "BC-CAN"]);
    });

    test("internal alerts", () {
      final monitor = Sp140AlertMonitor();
      expect(codes(monitor.update(healthy()..mcuTempDC = 600)), ["CPU-T"]);
      expect(codes(Sp140AlertMonitor().update(healthy()..baroPressureDHPa = 0)), ["Baro-I"]);
    });

    test("critical alerts sort first", () {
      final alerts = Sp140AlertMonitor().update(healthy()
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
  });
}
