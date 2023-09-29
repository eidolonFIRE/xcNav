import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart' as perm_handler_plat;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/main.dart';
import 'package:xcnav/models/waypoint.dart';
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
import 'package:xcnav/views/view_map.dart';
import 'package:xcnav/views/view_waypoints.dart';

import 'mock_providers.dart';

void main() {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.getInstance().then((prefs) {
    settingsMgr = SettingsMgr(prefs);
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

  patrolTest(
    'Create and delete a waypoint',
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

      // --- Make a waypoint
      await $(ViewMap).tester.tester.longPressAt(const Offset(300, 400));
      await $.waitUntilVisible($(Dialog));
      await $("Waypoint").tap(settlePolicy: SettlePolicy.noSettle);
      await $.waitUntilExists($(#editWaypointName));
      await $(#editWaypointName).enterText("my test waypoint", settlePolicy: SettlePolicy.noSettle);
      await $("Add").tap(settlePolicy: SettlePolicy.noSettle);

      // --- Check waypoint exists
      expect(activePlan.waypoints.length, 1);
      expect(activePlan.waypoints.values.first.name, "my test waypoint");

      // --- Delete the waypoint
      final bottomBarRect = $.tester.getRect($(BottomNavigationBar));
      await $.tester.tapAt(Offset(bottomBarRect.width * 3.5 / 5, bottomBarRect.top + bottomBarRect.height / 2));
      await $.waitUntilVisible($(ViewWaypoints));
      await $.tester.drag($(Slidable).$("my test waypoint"), const Offset(300, 0));
      await $.pump(const Duration(seconds: 2));
      await $(SlidableAction)
          .which<SlidableAction>((widget) => widget.backgroundColor == Colors.red)
          .tap(settlePolicy: SettlePolicy.noSettle);

      // --- Check waypoint deleted
      expect(activePlan.waypoints.length, 0);
    },
  );

  patrolTest(
    'Save waypoint to library',
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

      // --- Inject a waypoint
      activePlan.updateWaypoint(Waypoint(latlngs: [LatLng(10, 10)], name: "my test waypoint"));

      // --- Save waypoint collection
      final bottomBarRect = $.tester.getRect($(BottomNavigationBar));
      await $.tester.tapAt(Offset(bottomBarRect.width * 3.5 / 5, bottomBarRect.top + bottomBarRect.height / 2));
      await $.waitUntilVisible($(ViewWaypoints));
      await $(#viewWaypoints_moreOptions).tap(settlePolicy: SettlePolicy.noSettle);
      await $("Save").tap(settlePolicy: SettlePolicy.noSettle);
      await $(TextFormField).enterText("my test collection", settlePolicy: SettlePolicy.noSettle);
      await $.pump(const Duration(seconds: 2));
      await $(AlertDialog).$("Save").tap(settlePolicy: SettlePolicy.noSettle);
      await $.pump(const Duration(seconds: 1));
      await $.waitUntilVisible($("my test waypoint"));

      // --- Delete the waypoint
      await $.tester.drag($(Slidable).$("my test waypoint"), const Offset(300, 0));
      await $.pump(const Duration(seconds: 2));
      await $(SlidableAction)
          .which<SlidableAction>((widget) => widget.backgroundColor == Colors.red)
          .tap(settlePolicy: SettlePolicy.noSettle);

      // --- Check waypoint deleted, and still in collection
      expect(activePlan.waypoints.length, 0);
      await $(#viewWaypoints_moreOptions).tap(settlePolicy: SettlePolicy.noSettle);
      await $("Library").tap(settlePolicy: SettlePolicy.noSettle);
      await $.waitUntilVisible($("my test collection"));
      expect(plans.loadedPlans["my test collection"]?.waypoints.length, 1);
    },
  );
}
