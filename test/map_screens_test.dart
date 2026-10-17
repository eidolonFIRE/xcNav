import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/dialogs/label_flag.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/screens/log_replay.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/views/map/xc_map.dart';
import 'package:xcnav/widgets/flight_log_card.dart';
import 'package:xcnav/widgets/static_map.dart';

late Map<String, dynamic> enTranslations;

class _MapAssetLoader extends AssetLoader {
  const _MapAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async => enTranslations;
}

Future pumpApp(WidgetTester tester, Widget home, {Map<String, Object>? arguments}) async {
  await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale("en")],
      path: "assets/translations",
      assetLoader: const _MapAssetLoader(),
      startLocale: const Locale("en"),
      useOnlyLangCode: true,
      child: Builder(
          builder: (context) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(0.5)), child: child!),
                onGenerateRoute: (settings) => MaterialPageRoute(
                    builder: (_) => home, settings: RouteSettings(name: "/", arguments: arguments)),
              ))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

FlightLog makeLog() => FlightLog(samples: [
      Geo(lat: 37.0, lng: -122.0, alt: 100, timestamp: const Duration().inMilliseconds),
      Geo(lat: 37.0, lng: -121.9, alt: 300, spd: 15, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 37.05, lng: -121.85, alt: 320, spd: 20, timestamp: const Duration(minutes: 15).inMilliseconds),
      Geo(lat: 37.1, lng: -121.8, alt: 340, spd: 22, timestamp: const Duration(minutes: 20).inMilliseconds),
    ], waypoints: [
      Waypoint(name: "pin", latlngs: [const LatLng(37.02, -121.95)]),
      Waypoint(name: "path", latlngs: [const LatLng(37.0, -122.0), const LatLng(37.1, -121.9)]),
    ], fuelReports: [
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 1).inMilliseconds), 10.0),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 19).inMilliseconds), 6.0),
    ]);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    enTranslations = jsonDecode(File("assets/translations/en.json").readAsStringSync());
    settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
    configUnits(dist: DisplayUnitsDist.metric, fuel: DisplayUnitsFuel.liter);

    // MyTelemetry starts the accelerometer stream on construction.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      "dev.fluttercommunity.plus/sensors/method",
      "dev.fluttercommunity.plus/sensors/accelerometer",
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });

  testWidgets("log replay map shows the log, fuel reports, and the selected time", (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    logStore.logs["replayTest"] = makeLog();
    addTearDown(() => logStore.logs.remove("replayTest"));

    await pumpApp(tester, const LogReplay(), arguments: {"logKey": "replayTest"});
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(XcMap), findsOneWidget);
    expect(find.byType(LabelFlag), findsNWidgets(2));
    expect(find.image(const AssetImage("assets/images/red_arrow.png")), findsNothing);

    // Tapping a fuel report selects its time, which puts a marker on the map
    await tester.tap(find.descendant(of: find.byType(LabelFlag).first, matching: find.byType(Card)));
    await tester.pump();
    expect(find.image(const AssetImage("assets/images/red_arrow.png")), findsOneWidget);
  });

  testWidgets("flight log card preview", (tester) async {
    logStore.logs["cardTest"] = makeLog();
    addTearDown(() => logStore.logs.remove("cardTest"));

    await pumpApp(tester, const SingleChildScrollView(child: FlightLogCard("cardTest")));
    expect(find.byType(StaticMap), findsOneWidget);
    expect(find.byType(XcMap), findsNothing, reason: "lists use static previews, not native maps");
  });
}
