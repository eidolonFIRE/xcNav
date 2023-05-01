import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

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
import 'package:xcnav/providers/weather.dart';
import 'package:xcnav/providers/wind.dart';

import 'mock_providers.dart';

void main() {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.getInstance().then((prefs) {
    settingsMgr = SettingsMgr(prefs);
  });

  Widget makeApp(ActivePlan activePlan, MockPlans plans, Completer<MockClient> client) {
    return MultiProvider(providers: [
      ChangeNotifierProvider(
        create: (_) => MyTelemetry(),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (_) => Weather(),
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

  patrolTest(
    'Check chat bubble appears and clears',
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
        "profile.name": "Mr Test",
        "profile.id": "1234",
        "profile.secretID": "1234abcd",
      });
      final activePlan = ActivePlan();
      final plans = MockPlans();
      final clientCompleter = Completer<MockClient>();

      // --- Build App
      await $.pumpWidget(makeApp(activePlan, plans, clientCompleter));
      await $.waitUntilExists($(Scaffold));

      final client = await clientCompleter.future;

      // --- Join a group
      client.handleAuthResponse({
        "status": 0,
        "secretToken": "1234abcd",
        "pilot_id": "1234",
        "pilotMetaHash": "cb3b4",
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
          .tap(andSettle: false);
      await $.pump(const Duration(seconds: 30));
    },
  );
}
