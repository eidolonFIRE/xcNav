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
import 'package:xcnav/providers/weather.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/settings_service.dart';

import 'mock_providers.dart';

void main() {
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
        create: (context) => Weather(context),
        lazy: false,
      ),
      ChangeNotifierProvider(
        create: (context) => Wind(),
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

  patrolTest(
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
        "profile.name": "Mr Test",
        "profile.id": "1234",
        "profile.secretID": "1234abcd",
      });

      // --- Build App
      await $.pumpWidget(makeApp());
      await $.waitUntilExists($(Scaffold));

      // --- Open flight logs screen
      await $.tester.tapAt($.tester.getBottomLeft($(MaterialApp)) + const Offset(20, -20));
      await $.pump(const Duration(seconds: 2));
      await $("Log").tap(andSettle: false);

      // --- Select Stats tile
      await $.waitUntilExists($("Entries"));
      await $("Stats").tap(andSettle: false);
      await $.pump(const Duration(seconds: 2));
    },
  );
}
