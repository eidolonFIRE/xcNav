import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mockito/mockito.dart';
import 'package:mocktail_image_network/mocktail_image_network.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:provider/provider.dart';

import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart' as perm_handler_plat;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/main.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/settings_service.dart';

import 'mock_providers.dart';

import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final MockFlutterLocalNotificationsPlugin mock = MockFlutterLocalNotificationsPlugin();
  FlutterLocalNotificationsPlatform.instance = mock;
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.getInstance().then((prefs) {
    settingsMgr = SettingsMgr(prefs);
  });

  Widget makeApp() {
    return MultiProvider(providers: [
      ChangeNotifierProvider(
        create: (_) => MyTelemetry(),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (_) => Wind(),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (_) => ActivePlan(),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (_) => Plans(),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (_) => Profile(),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (_) => Group(),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (_) => ChatMessages(),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (context) => ADSB(context),
        lazy: false,
      ),
      ChangeNotifierProvider(
        // ignore: unnecessary_cast
        create: (context) => MockClient(context) as Client,
        lazy: false,
      )
    ], child: const XCNav());
  }

  setUp(() async {
    final flamante = rootBundle.load('assets/fonts/roboto-condensed.regular.ttf');
    final fontLoader = FontLoader('roboto-condensed')..addFont(flamante);
    await fontLoader.load();
  });
  patrolWidgetTest(
    'Flight Logs: loads with no logs',
    ($) async {
      // --- Setup stubs and initial configs
      GeolocatorPlatform.instance = MockGeolocatorPlatform();
      perm_handler_plat.PermissionHandlerPlatform.instance = MockPermissionHandlerPlatform();
      when(GeolocatorPlatform.instance.getServiceStatusStream()).thenAnswer((_) => Stream.value(ServiceStatus.enabled));
      when(GeolocatorPlatform.instance.getPositionStream(
          locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: null,
      ))).thenAnswer((_) => Stream.value(mockPosition));
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      SharedPreferences.setMockInitialValues({
        "weatherKit.last.time": clock.now().millisecondsSinceEpoch - 10000,
        "weatherKit.last.value": 1351.0,
        "weatherKit.last.lat": 37.0,
        "weatherKit.last.lng": -121.0,
        "profile.name": "Mr Test",
        "profile.id": "1234",
        "profile.secretID": "1234abcd",
      });

      // --- Build App
      await mockNetworkImages(() async => $.pumpWidget(makeApp()));
      await $.pumpWidget(makeApp());
      await $.waitUntilExists($(Scaffold));

      // --- Open flight logs screen
      await $.tester.tapAt($.tester.getBottomLeft($(MaterialApp)) + const Offset(30, -30));
      await $.pump(const Duration(seconds: 2));
      await $.tester.drag($("ADSB-in"), const Offset(0, -300));
      await $.pump(const Duration(seconds: 2));
      await $("Log").tap(settlePolicy: SettlePolicy.noSettle);

      // // --- Select Stats tile
      await $.waitUntilExists($("Entries"));
      await $("Stats").tap(settlePolicy: SettlePolicy.noSettle);
      await $.pump(const Duration(seconds: 2));
    },
  );
}

class MockMethodChannel extends Mock implements MethodChannel {}

class MockFlutterLocalNotificationsPlugin extends Mock
    with
        MockPlatformInterfaceMixin // ignore: prefer_mixin
    implements
        FlutterLocalNotificationsPlatform {}
