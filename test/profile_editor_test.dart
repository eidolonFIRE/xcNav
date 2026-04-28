import 'package:easy_localization/easy_localization.dart';
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
import 'package:xcnav/locale.dart';

import 'package:xcnav/main.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/settings_service.dart';

import 'mock_providers.dart';

import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  final MockFlutterLocalNotificationsPlugin mock = MockFlutterLocalNotificationsPlugin();
  FlutterLocalNotificationsPlatform.instance = mock;

  Widget makeApp() {
    return EasyLocalization(
        supportedLocales: supportedLanguages.values.nonNulls.toList(),
        path: "assets/translations",
        fallbackLocale: const Locale("en"),
        useFallbackTranslations: true,
        useFallbackTranslationsForEmptyResources: true,
        startLocale: const Locale("en"),
        useOnlyLangCode: true,
        child: MultiProvider(providers: [
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
        ], child: const XCNav()));
  }

  setUp(() async {
    final flamante = rootBundle.load('assets/fonts/roboto-condensed.regular.ttf');
    final fontLoader = FontLoader('roboto-condensed')..addFont(flamante);
    await fontLoader.load();
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      "profile.name": "Mr Test",
      "profile.id": "1234",
      "profile.secretID": "1234abcd",
    });
    settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
    settingsMgr.hideWeatherObservations.value = true;
  });

  patrolWidgetTest(
    'Get to profile editor',
    ($) async {
      // --- override size
      $.tester.view.physicalSize = const Size(800, 2000);
      $.tester.view.devicePixelRatio = 1.0;

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

      // --- When profile isn't set...
      SharedPreferences.setMockInitialValues({
        // "profile.name": "Mr Test",
        // "profile.id": "1234",
        // "profile.secretID": "1234abcd",
      });

      // --- Build App
      await mockNetworkImages(() async => $.pumpWidget(makeApp()));
      // await $.pumpWidget(makeApp());
      await $.waitUntilExists($(Scaffold));

      //
      await $.pump(const Duration(seconds: 2));

      //
      await $.waitUntilExists($("Edit Profile"));
    },
  );
}

class MockMethodChannel extends Mock implements MethodChannel {}

class MockFlutterLocalNotificationsPlugin extends Mock
    with
        MockPlatformInterfaceMixin // ignore: prefer_mixin
    implements
        FlutterLocalNotificationsPlatform {}
