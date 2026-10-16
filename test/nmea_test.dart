import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:xcnav/ble_devices/ble_device_stodeus.dart';
import 'package:xcnav/models/nmea.dart';
import 'package:xcnav/services/ble_service.dart';
import 'package:xcnav/views/map/link_status_icon.dart';

const gga = "\$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47";
const rmc = "\$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A";

/// Wrap a sentence body with `$` and a valid checksum
String withChecksum(String body) {
  int sum = 0;
  for (final c in body.codeUnits) {
    sum ^= c;
  }
  return "\$$body*${sum.toRadixString(16).padLeft(2, "0").toUpperCase()}";
}

void main() {
  group("nmeaBody", () {
    test("valid checksum", () {
      expect(nmeaBody(gga), startsWith("GPGGA,123519"));
    });

    test("bad checksum", () {
      expect(nmeaBody(gga.replaceFirst("545.4", "545.5")), isNull);
    });

    test("no checksum", () {
      expect(nmeaBody("\$LK8EX1,101325,99999,9999,99,999,"), "LK8EX1,101325,99999,9999,99,999,");
    });

    test("garbage before sentence", () {
      expect(nmeaBody("1,E,1,08\$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47"),
          startsWith("GPGGA"));
    });
  });

  group("NmeaLineSplitter", () {
    test("reassembles fragments", () {
      final splitter = NmeaLineSplitter();
      final bytes = ascii.encode("$gga\r\n$rmc\r\n\$LK8");
      final lines = <String>[];
      for (int i = 0; i < bytes.length; i += 20) {
        lines.addAll(splitter.add(bytes.sublist(i, i + 20 > bytes.length ? bytes.length : i + 20)));
      }
      expect(lines, [gga, rmc]);
      expect(splitter.add(ascii.encode("EX1\n")), ["\$LK8EX1"]);
    });
  });

  group("Lk8ex1", () {
    test("parses fields", () {
      final lk = Lk8ex1.parse(nmeaBody(withChecksum("LK8EX1,98765,99999,-152,23,1085,"))!)!;
      expect(lk.pressure, closeTo(987.65, 0.001));
      expect(lk.altitude, isNull);
      expect(lk.vario, closeTo(-1.52, 0.001));
      expect(lk.temperature, 23);
      expect(lk.batteryPercent, 85);
      expect(lk.batteryVolts, isNull);
    });

    test("missing values and battery voltage", () {
      final lk = Lk8ex1.parse("LK8EX1,999999,1234,9999,99,3.9,")!;
      expect(lk.pressure, isNull);
      expect(lk.altitude, 1234);
      expect(lk.vario, isNull);
      expect(lk.temperature, isNull);
      expect(lk.batteryPercent, isNull);
      expect(lk.batteryVolts, 3.9);
    });

    test("rejects other sentences", () {
      expect(Lk8ex1.parse(nmeaBody(gga)!), isNull);
    });
  });

  group("GGA / RMC", () {
    test("GGA", () {
      final fix = NmeaGga.parse(nmeaBody(gga)!)!;
      expect(fix.timeOfDay, ((12 * 60 + 35) * 60 + 19) * 1000);
      expect(fix.lat, closeTo(48.1173, 0.0001));
      expect(fix.lng, closeTo(11.516667, 0.0001));
      expect(fix.fixQuality, 1);
      expect(fix.satellites, 8);
      expect(fix.hdop, 0.9);
      expect(fix.altitude, 545.4);
    });

    test("RMC", () {
      final fix = NmeaRmc.parse(nmeaBody(rmc)!)!;
      expect(fix.time, DateTime.utc(2094, 3, 23, 12, 35, 19));
      expect(fix.valid, true);
      expect(fix.speed, closeTo(22.4 * 0.514444, 0.001));
      expect(fix.course, 84.4);
    });

    test("southern / western hemisphere and GN talker", () {
      final fix = NmeaGga.parse("GNGGA,010203.50,3345.000,S,11830.000,W,1,10,1.0,100.0,M,0,M,,")!;
      expect(fix.timeOfDay, 3723500);
      expect(fix.lat, closeTo(-33.75, 1e-9));
      expect(fix.lng, closeTo(-118.5, 1e-9));
    });
  });

  group("NmeaFixAssembler", () {
    test("emits once both sentences of an epoch arrive", () {
      final assembler = NmeaFixAssembler();
      expect(assembler.addRmc(NmeaRmc.parse(nmeaBody(rmc)!)!), isNull);
      final position = assembler.addGga(NmeaGga.parse(nmeaBody(gga)!)!)!;
      expect(position.latitude, closeTo(48.1173, 0.0001));
      expect(position.altitude, 545.4);
      expect(position.timestamp.toUtc(), DateTime.utc(2094, 3, 23, 12, 35, 19));
      expect(position.accuracy, closeTo(4.5, 0.001));
    });

    test("mismatched epochs don't pair", () {
      final assembler = NmeaFixAssembler();
      assembler.addGga(NmeaGga.parse(nmeaBody(gga)!)!);
      expect(assembler.addRmc(NmeaRmc.parse("GPRMC,123520,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W")!),
          isNull);
    });

    test("no fix", () {
      final assembler = NmeaFixAssembler();
      assembler.addGga(NmeaGga.parse(nmeaBody(gga)!)!);
      expect(assembler.addRmc(NmeaRmc.parse("GPRMC,123519,V,4807.038,N,01131.000,E,0,0,230394,,")!), isNull);
    });
  });

  group("BleDeviceStodeus", () {
    test("matched by name", () {
      for (final name in ["UltraBip", "UltraBip 1234", "ULTRABIP_0042", "BlueBip 7", "Stodeus"]) {
        expect(getHandler(name: name), bleDeviceStodeus, reason: name);
      }
      expect(getHandler(name: "Bip"), isNull);
    });

    test("forwards baro and position", () {
      final device = BleDeviceStodeus();
      final baros = <List<double?>>[];
      final positions = <Position>[];
      device.onBaro = (pressure, vario) => baros.add([pressure, vario]);
      device.onPosition = positions.add;

      device.handleBytes(ascii.encode("${withChecksum("LK8EX1,101325,99999,50,20,1100,")}\r\n$gga\r\n$rmc\r\n"));

      expect(baros, [
        [1013.25, 0.5]
      ]);
      expect(device.batteryPercent.value, 100);
      expect(device.temperature.value, 20);
      expect(positions.length, 1);
      expect(positions.first.longitude, closeTo(11.516667, 0.0001));
    });

    testWidgets("status follows connection and data", (tester) async {
      final device = BleDeviceStodeus();
      expect(device.attached.value, false);
      expect(device.status.value, VarioStatus.disconnected);

      device.device = BluetoothDevice.fromId("C7:7F:28:14:A0:1D");
      expect(device.attached.value, true);

      device.handleBytes(ascii.encode("\$LK8"));
      expect(device.status.value, VarioStatus.receiving);

      // Data stops
      await tester.pump(BleDeviceStodeus.dataTimeout + const Duration(seconds: 1));
      expect(device.status.value, VarioStatus.connected);

      // User disconnects
      device.handleBytes(ascii.encode("\$LK8"));
      device.device = null;
      expect(device.attached.value, false);
      expect(device.status.value, VarioStatus.disconnected);
      await tester.pump(BleDeviceStodeus.dataTimeout + const Duration(seconds: 1));
      expect(device.status.value, VarioStatus.disconnected, reason: "watchdog cancelled");
    });

    test("status color", () {
      expect(varioStatusColor(VarioStatus.receiving), Colors.green);
      expect(varioStatusColor(VarioStatus.disconnected), Colors.red);
    });
  });
}
