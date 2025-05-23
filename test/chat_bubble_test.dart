import 'dart:async';

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
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/providers/wind.dart';

import 'mock_providers.dart';

import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final MockFlutterLocalNotificationsPlugin mock = MockFlutterLocalNotificationsPlugin();
  FlutterLocalNotificationsPlatform.instance = mock;

  Widget makeApp(ActivePlan activePlan, MockPlans plans, Completer<MockClient> client) {
    return MultiProvider(providers: [
      ChangeNotifierProvider(
        create: (_) => MyTelemetry(),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (context) => Wind(),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (_) => activePlan,
        lazy: false,
      ),
      ChangeNotifierProvider(
        // ignore: unnecessary_cast
        create: (_) => plans as Plans,
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
        create: (context) {
          final fakeClient = MockClient(context);
          client.complete(fakeClient);
          // ignore: unnecessary_cast
          return fakeClient as Client;
        },
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
    'Check chat bubble appears and clears',
    ($) async {
      SharedPreferences.setMockInitialValues({
        "weatherKit.last.time": clock.now().millisecondsSinceEpoch - 10000,
        "weatherKit.last.value": 1351.0,
        "weatherKit.last.lat": 37.0,
        "weatherKit.last.lng": -121.0,
        "profile.name": "Mr Test",
        "profile.id": "1234",
        "profile.secretID": "1234abcd",
      });
      SharedPreferences.getInstance().then((prefs) {
        settingsMgr = SettingsMgr(prefs);
      });

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
      final activePlan = ActivePlan();
      final plans = MockPlans();
      final clientCompleter = Completer<MockClient>();

      // --- Build App
      await mockNetworkImages(() async => $.pumpWidget(makeApp(activePlan, plans, clientCompleter)));
      await $.waitUntilExists($(Scaffold));

      final client = await clientCompleter.future;

      // --- Join a group
      client.handleAuthResponse({
        "status": 0,
        "secretToken": "1234abcd",
        "pilot_id": "1234",
        "pilotMetaHash": "a938aa",
        "apiVersion": 7,
        "group_id": "6f3a49"
      });

      client.handleGroupInfoResponse({
        "status": 0,
        "group_id": "6f3a49",
        "pilots": [
          {"id": "otherPilotID1234", "name": "bender", "avatarHash": "b96e3cff738b67359e2896db92a11284"}
        ],
        "waypoints": {
          "ld6k9yb82t7h61": {
            "id": "ld6k9yb82t7h61",
            "name": "Hospital Canyon",
            "latlng": [
              [37.55983, -121.37429]
            ],
            "icon": null,
            "color": 4278190080
          },
        }
      });

      // --- Test a short message
      client.handleChatMessage({
        "timestamp": DateTime.now().millisecondsSinceEpoch,
        "group_id": "6f3a49",
        "pilot_id": "otherPilotID1234",
        "text": "testing",
        "emergency": false
      });

      await $.waitUntilVisible($("testing"));

      // --- Test a long message
      client.handleChatMessage({
        "timestamp": DateTime.now().millisecondsSinceEpoch,
        "group_id": "6f3a49",
        "pilot_id": "otherPilotID1234",
        "text": "ok, this is a long message example. It should line-wrap in the display.",
        "emergency": false
      });

      await $
          .waitUntilVisible($("ok, this is a long message example. It should line-wrap in the display."))
          .tap(settlePolicy: SettlePolicy.noSettle);
      await $.pump(const Duration(seconds: 30));
    },
  );
}

class MockMethodChannel extends Mock implements MethodChannel {}

class MockFlutterLocalNotificationsPlugin extends Mock
    with
        MockPlatformInterfaceMixin // ignore: prefer_mixin
    implements
        FlutterLocalNotificationsPlatform {}
