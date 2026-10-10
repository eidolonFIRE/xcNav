import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/dialogs/flight_detection_dialog.dart';
import 'package:xcnav/settings_service.dart';

import 'test_localization.dart';

void main() {
  setUpAll(() async {
    await initTestLocalization();
    settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
  });

  Future pumpDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testLocalization(
        child: Builder(
            builder: (context) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                home: const Scaffold(body: FlightDetectionDialog())))));
    await tester.pumpAndSettle();
  }

  testWidgets("toggles update settings and disable sliders", (tester) async {
    await pumpDialog(tester);

    expect(find.text("Takeoff"), findsOneWidget);
    expect(find.text("Landing"), findsOneWidget);
    expect(find.byType(RangeSlider), findsOneWidget);

    expect(settingsMgr.launchUseAgl.value, true);
    await tester.tap(find.text("Above the ground"));
    await tester.pumpAndSettle();
    expect(settingsMgr.launchUseAgl.value, false);
    // Height slider is now disabled
    final heightSlider = tester.widget<Slider>(find.byType(Slider).first);
    expect(heightSlider.onChanged, isNull);
    // "Either one" hint only shows when both are enabled
    expect(find.textContaining("Either one"), findsNothing);
  });

  testWidgets("reset restores defaults", (tester) async {
    settingsMgr.launchUseVario.value = false;
    settingsMgr.landingHoldTime.value = 90;
    settingsMgr.launchMinSpeed.value = 1;
    await pumpDialog(tester);

    await tester.tap(find.text("Reset to Defaults"));
    await tester.pumpAndSettle();

    expect(settingsMgr.launchUseVario.value, true);
    expect(settingsMgr.landingHoldTime.value, 20);
    expect(settingsMgr.launchMinSpeed.value, 4.0);
  });
}
