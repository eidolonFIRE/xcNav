import 'package:flutter/services.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mockito/mockito.dart';
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
import 'package:xcnav/providers/weather.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/settings_service.dart';

import 'mock_providers.dart';

void main() {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.getInstance().then((prefs) {
    settingsMgr = SettingsMgr(prefs);
    // settingsMgr.showAirspaceOverlay.value = false;
  });

  Widget makeApp(ActivePlan activePlan, MockPlans plans) {
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
        create: (_) => Wind(),
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
    'Get to home screen',
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

      // --- Build App
      await $.pumpWidget(makeApp(activePlan, plans));
      await $.waitUntilExists($(Scaffold));

      //
      await $.pump(const Duration(seconds: 2));
    },
  );

  patrolWidgetTest(
    'Change base map in main view',
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

      // --- Build App
      await $.pumpWidget(makeApp(activePlan, plans));
      await $.waitUntilExists($(Scaffold));
      await $.pump(const Duration(seconds: 2));

      // --- Default map layer
      expect(settingsMgr.mainMapTileSrc.value, MapTileSrc.topo);
      expect(settingsMgr.mainMapOpacity.value, 1);

      // --- Select a different map
      await $(#viewMap_mapSelector).tap(settlePolicy: SettlePolicy.noSettle);
      await $.waitUntilVisible($(SpeedDial));
      await $(#mapSelector_satellite_60).tap(settlePolicy: SettlePolicy.noSettle);

      // (let the speeddial finish the animation)
      await $.pump(const Duration(seconds: 2));

      // --- New map layer
      expect(settingsMgr.mainMapTileSrc.value, MapTileSrc.satellite);
      expect(settingsMgr.mainMapOpacity.value, 0.6);
    },
  );
}
