import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mockito/mockito.dart';
import 'package:mocktail_image_network/mocktail_image_network.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:provider/provider.dart';

import 'package:flutter/material.dart';

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
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/views/view_map.dart';
import 'package:xcnav/views/view_waypoints.dart';

import 'mock_providers.dart';

import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final MockFlutterLocalNotificationsPlugin mock = MockFlutterLocalNotificationsPlugin();
  FlutterLocalNotificationsPlatform.instance = mock;

  Widget makeApp(ActivePlan activePlan, MockPlans plans) {
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
    'Create and delete a waypoint',
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
        // settingsMgr.showAirspaceOverlay.value = false;
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

      // --- Build App
      await mockNetworkImages(() async => $.pumpWidget(makeApp(activePlan, plans)));
      // await $.pumpWidget(makeApp(activePlan, plans));
      await $.waitUntilExists($(Scaffold));
      await $.pump(const Duration(seconds: 2));

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

  patrolWidgetTest('Save waypoint to library', ($) async {
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
      // settingsMgr.showAirspaceOverlay.value = false;
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

    // --- Build App
    await mockNetworkImages(() async => $.pumpWidget(makeApp(activePlan, plans)));
    // await $.pumpWidget(makeApp(activePlan, plans));
    await $.waitUntilExists($(Scaffold));

    // --- Inject a waypoint
    activePlan.updateWaypoint(Waypoint(latlngs: [const LatLng(10, 10)], name: "my test waypoint"));

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
  });
}

class MockMethodChannel extends Mock implements MethodChannel {}

class MockFlutterLocalNotificationsPlugin extends Mock
    with
        MockPlatformInterfaceMixin // ignore: prefer_mixin
    implements
        FlutterLocalNotificationsPlatform {}
