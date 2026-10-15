import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/dialogs/wind_dialog.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/screens/big_instruments.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';
import 'package:xcnav/widgets/top_instruments.dart';
import 'package:xcnav/widgets/windicator.dart';

late Map<String, dynamic> enTranslations;

class _MapAssetLoader extends AssetLoader {
  const _MapAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async => enTranslations;
}

/// Pump an app with the home route showing [TopInstruments] and the big instruments route registered.
Future pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale("en")],
      path: "assets/translations",
      assetLoader: const _MapAssetLoader(),
      startLocale: const Locale("en"),
      useOnlyLangCode: true,
      child: ChangeNotifierProvider(
        create: (_) => Wind(),
        child: Builder(
            builder: (context) => MaterialApp(
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: context.localizationDelegates,
                  // Test font (Ahem) is much wider than real fonts; keep the top bar from overflowing.
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(0.5)), child: child!),
                  routes: {
                    "/": (context) => Scaffold(
                        appBar: AppBar(
                            toolbarHeight: topInstrumentsHeight, title: TopInstruments(myTelemetry: myTelemetry))),
                    "/bigInstruments": (context) => const BigInstruments(),
                  },
                )),
      )));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    enTranslations = jsonDecode(File("assets/translations/en.json").readAsStringSync());
    settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
    configUnits(dist: DisplayUnitsDist.metric, speed: DisplayUnitsSpeed.kph);

    // MyTelemetry starts the accelerometer stream on construction.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      "dev.fluttercommunity.plus/sensors/method",
      "dev.fluttercommunity.plus/sensors/accelerometer",
      "dev.fluttercommunity.plus/sensors/barometer",
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });

  setUp(() {
    myTelemetry.geo = Geo(alt: 1234)..ground = 234;
    myTelemetry.speedSmooth.value = 10;
    settingsMgr.primaryAltimeter.value = AltimeterMode.msl;
  });

  testWidgets("tap ground speed opens big instruments, tap again closes", (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    expect(find.byType(BigInstruments), findsNothing);

    // 10 m/s == 36 kph
    await tester.tap(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith("36")).first);
    await tester.pumpAndSettle();
    expect(find.byType(BigInstruments), findsOneWidget);

    await tester.tap(find.byKey(const Key("bigInstruments_speed")));
    await tester.pumpAndSettle();
    expect(find.byType(BigInstruments), findsNothing);
  });

  testWidgets("shows primary and secondary altitude; double tap swaps", (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    Navigator.of(tester.element(find.byType(TopInstruments))).pushNamed("/bigInstruments");
    await tester.pumpAndSettle();

    final big = find.byType(BigInstruments);
    expect(find.descendant(of: big, matching: find.text("1234")), findsOneWidget);
    expect(find.descendant(of: big, matching: find.text("1000")), findsOneWidget);
    expect(find.descendant(of: big, matching: find.text("MSL")), findsOneWidget);

    final alt = find.byKey(const Key("bigInstruments_altimeter"));
    await tester.tap(alt);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(alt);
    await tester.pumpAndSettle();
    expect(settingsMgr.primaryAltimeter.value, AltimeterMode.agl);
  });

  testWidgets("tap wind swaps wind details in place of the indicator", (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    Navigator.of(tester.element(find.byType(TopInstruments))).pushNamed("/bigInstruments");
    await tester.pumpAndSettle();

    final big = find.byType(BigInstruments);
    await tester.tap(find.descendant(of: big, matching: find.byType(Windicator)));
    // Detector shows a spinner while waiting for samples, so don't settle.
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsNothing);
    expect(find.descendant(of: big, matching: find.byType(WindDialog)), findsOneWidget);
    expect(find.descendant(of: big, matching: find.byType(Windicator)), findsNothing);
    // Instruments still visible
    expect(find.descendant(of: big, matching: find.text("1234")), findsOneWidget);

    await tester.tap(find.byKey(const Key("windDialog_close")));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(WindDialog), findsNothing);
    expect(find.descendant(of: big, matching: find.byType(Windicator)), findsOneWidget);
  });

  testWidgets("lays out in landscape without overflow", (tester) async {
    tester.view.physicalSize = const Size(2340, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    Navigator.of(tester.element(find.byType(TopInstruments))).pushNamed("/bigInstruments");
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BigInstruments), findsOneWidget);
  });
}
