import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/ble_devices/ble_device_meshtastic.dart';
import 'package:xcnav/services/ble_service.dart';

void main() {
  group('isHandlerDevice', () {
    test('no device associated', () {
      final handler = BleDeviceMeshtastic();
      expect(isHandlerDevice(handler, const DeviceIdentifier("EF:AD:98:1E:06:B3")), false);
    });

    test('matches associated device', () {
      final handler = BleDeviceMeshtastic();
      handler.device = BluetoothDevice.fromId("C7:7F:28:14:A0:1D");
      expect(isHandlerDevice(handler, const DeviceIdentifier("C7:7F:28:14:A0:1D")), true);
    });

    test('other device sharing the same handler does not match', () {
      // Two Meshtastic nodes in range share one handler; the second must not be treated as the connected one.
      final handler = BleDeviceMeshtastic();
      handler.device = BluetoothDevice.fromId("C7:7F:28:14:A0:1D");
      expect(isHandlerDevice(handler, const DeviceIdentifier("EF:AD:98:1E:06:B3")), false);
    });
  });
}
