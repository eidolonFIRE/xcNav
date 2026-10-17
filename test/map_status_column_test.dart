import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/ble_devices/ble_device_sp140.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/services/ble_service.dart' as ble_service;
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/views/map/map_status_column.dart';

/// Default no-op platform; lets the status cards subscribe to connection state in tests.
final class FakeBlePlatform extends FlutterBluePlusPlatform {}

Future pumpColumn(WidgetTester tester) async {
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Profile()),
        ChangeNotifierProvider(create: (_) => Group()),
        ChangeNotifierProvider(create: (_) => ChatMessages()),
      ],
      child: const MaterialApp(home: Scaffold(body: MapStatusColumn()))));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    settingsMgr = SettingsMgr(await SharedPreferences.getInstance());

    // MyTelemetry starts the accelerometer stream on construction.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      "dev.fluttercommunity.plus/sensors/method",
      "dev.fluttercommunity.plus/sensors/accelerometer",
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    FlutterBluePlusPlatform.instance = FakeBlePlatform();
  });

  tearDown(() => ble_service.bleDeviceSp140.device = null);

  testWidgets("Sp140StatusCard hidden without a device", (tester) async {
    await pumpColumn(tester);

    expect(find.byType(Sp140StatusCard), findsNothing);
  });

  testWidgets("Sp140StatusCard appears when SP140 attaches after first build", (tester) async {
    await pumpColumn(tester);
    expect(find.byType(Sp140StatusCard), findsNothing);

    // Device connects while the map is already showing.
    ble_service.bleDeviceSp140.device = BluetoothDevice.fromId("C7:7F:28:14:A0:1D");
    await tester.pump();
    expect(find.byType(Sp140StatusCard), findsOneWidget);

    // Manual fuel button is replaced by the SP140 card.
    expect(find.byIcon(Icons.local_gas_station), findsNothing);

    ble_service.bleDeviceSp140.device = null;
    await tester.pump();
    expect(find.byType(Sp140StatusCard), findsNothing);
    expect(find.byIcon(Icons.local_gas_station), findsOneWidget);
  });
}
