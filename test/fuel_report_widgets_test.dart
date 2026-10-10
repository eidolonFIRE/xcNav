import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/dialogs/edit_live_fuel_report.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/screens/log_replay.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/log_summary.dart';

DateTime minutes(int m) => DateTime.fromMillisecondsSinceEpoch(Duration(minutes: m).inMilliseconds);

List<Geo> makeSamples() => [
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.05, lng: 120.15, alt: 220, spd: 23.0537096, timestamp: const Duration(minutes: 15).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ];

late Map<String, dynamic> enTranslations;

class _MapAssetLoader extends AssetLoader {
  const _MapAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async => enTranslations;
}

/// Pump [child] inside a localized MaterialApp.
/// Text is scaled down because the test font (Ahem) is much wider than real fonts,
/// which would otherwise overflow fixed-width widgets like FuelEntryCard.
Future pumpWrapped(WidgetTester tester, Widget child) async {
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
              home: Scaffold(body: child)))));
  await tester.pumpAndSettle();
}

/// Find a widget whose full text (including TextSpan children) contains [text].
Finder findRichTextContaining(String text) =>
    find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains(text));

/// Fuel amount as rendered by `richValue` in FuelEntryCard, e.g. "5.5 L".
String fuelAmountText(double amount) =>
    "${printValue(UnitType.fuel, amount, decimals: 1)} ${getUnitStr(UnitType.fuel)}";

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    enTranslations = jsonDecode(File("assets/translations/en.json").readAsStringSync());
    settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
    settingsMgr.forceGpsAltitude.value = true;
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

  group("LogSummary", () {
    testWidgets("hides fuel stats with fewer than two reports", (tester) async {
      final log = FlightLog(samples: makeSamples(), fuelReports: [FuelReport(minutes(1), 10)]);

      await pumpWrapped(tester, LogSummary(log: log));

      expect(find.text("log_summary.Fuel Burn Rate".tr()), findsNothing);
      expect(find.text("log_summary.Fuel Efficiency".tr()), findsNothing);
    });

    testWidgets("shows fuel burn rate and efficiency from the controller", (tester) async {
      final log = FlightLog(samples: makeSamples(), fuelReports: [
        FuelReport(minutes(1), 10),
        FuelReport(minutes(10), 5),
      ]);

      await pumpWrapped(tester, LogSummary(log: log));

      // Reports passed in at construction (e.g. a log loaded from file) must produce stats.
      expect(find.text("log_summary.Fuel Burn Rate".tr()), findsOneWidget);
      expect(find.text("log_summary.Fuel Efficiency".tr()), findsOneWidget);

      final stat = log.fuelReportController.getSumFuelStat(log.samples)!;
      // 5L burned over 9 minutes
      expect(stat.rate, closeTo(5 / (9 / 60), 0.0001));
      expect(
          findRichTextContaining("${printValue(UnitType.fuel, stat.rate, decimals: 1)}$fuelRateStr"), findsOneWidget);
      expect(
          findRichTextContaining(
              "${printValue(UnitType.distCoarse, stat.mpl / unitConverters[UnitType.fuel]!(1), decimals: 1)}$fuelEffStr"),
          findsOneWidget);
    });

    testWidgets("updates when reports are inserted and removed", (tester) async {
      final log = FlightLog(samples: makeSamples(), fuelReports: [FuelReport(minutes(1), 10)]);
      late StateSetter rebuild;

      await pumpWrapped(tester, StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return LogSummary(log: log);
      }));
      expect(find.text("log_summary.Fuel Burn Rate".tr()), findsNothing);

      // Adding a second report should invalidate the stat cache and show stats.
      rebuild(() => log.fuelReportController.insertFuelReport(minutes(10), 5));
      await tester.pump();
      expect(find.text("log_summary.Fuel Burn Rate".tr()), findsOneWidget);
      final firstRate = log.fuelReportController.getSumFuelStat(log.samples)!.rate;
      expect(
          findRichTextContaining("${printValue(UnitType.fuel, firstRate, decimals: 1)}$fuelRateStr"), findsOneWidget);

      // Changing a report should change the displayed rate.
      rebuild(() => log.fuelReportController.insertFuelReport(minutes(10), 7));
      await tester.pump();
      final secondRate = log.fuelReportController.getSumFuelStat(log.samples)!.rate;
      expect(secondRate, isNot(firstRate));
      expect(
          findRichTextContaining("${printValue(UnitType.fuel, secondRate, decimals: 1)}$fuelRateStr"), findsOneWidget);

      // Removing back down to a single report hides stats again.
      rebuild(() => log.fuelReportController.removeFuelReport(1));
      await tester.pump();
      expect(find.text("log_summary.Fuel Burn Rate".tr()), findsNothing);
    });
  });

  group("FuelEntryCard", () {
    testWidgets("shows report time and amount", (tester) async {
      final log = FlightLog(samples: makeSamples(), fuelReports: [
        FuelReport(minutes(1), 10),
        FuelReport(minutes(10), 5.5),
      ]);

      await pumpWrapped(tester, FuelEntryCard(log: log, reportIndex: 1));

      expect(find.text(intl.DateFormat("h:mm a").format(minutes(10))), findsOneWidget);
      expect(findRichTextContaining(fuelAmountText(5.5)), findsOneWidget);
    });

    testWidgets("edit button reports its index", (tester) async {
      final log = FlightLog(samples: makeSamples(), fuelReports: [
        FuelReport(minutes(1), 10),
        FuelReport(minutes(10), 5),
      ]);
      int? edited;

      await pumpWrapped(tester, FuelEntryCard(log: log, reportIndex: 1, onEdit: (i) => edited = i));
      await tester.tap(find.byIcon(Icons.edit));

      expect(edited, 1);
    });

    testWidgets("reflects updateFuelReport", (tester) async {
      final log = FlightLog(samples: makeSamples(), fuelReports: [
        FuelReport(minutes(1), 10),
        FuelReport(minutes(10), 5),
      ]);
      late StateSetter rebuild;

      await pumpWrapped(tester, StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return FuelEntryCard(log: log, reportIndex: 0);
      }));

      rebuild(() => log.fuelReportController.updateFuelReport(0, 9.5, time: minutes(2)));
      await tester.pump();

      expect(log.fuelReportController.fuelReports.length, 2);
      expect(find.text(intl.DateFormat("h:mm a").format(minutes(2))), findsOneWidget);
      expect(findRichTextContaining(fuelAmountText(9.5)), findsOneWidget);
    });

    testWidgets("updateFuelReport without a time keeps the report's time", (tester) async {
      final log = FlightLog(samples: makeSamples(), fuelReports: [
        FuelReport(minutes(1), 10),
        FuelReport(minutes(10), 5),
      ]);
      late StateSetter rebuild;

      await pumpWrapped(tester, StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return FuelEntryCard(log: log, reportIndex: 1);
      }));

      rebuild(() => log.fuelReportController.updateFuelReport(1, 4));
      await tester.pump();

      expect(log.fuelReportController.fuelReports.length, 2);
      expect(log.fuelReportController.fuelReports[1].time, minutes(10));
      expect(find.text(intl.DateFormat("h:mm a").format(minutes(10))), findsOneWidget);
      expect(findRichTextContaining(fuelAmountText(4)), findsOneWidget);
    });
  });

  group("editLiveFuelReport", () {
    setUp(() {
      myTelemetry.fuelReportController = FuelReportController();
      myTelemetry.recordGeo = [];
      myTelemetry.takeOff = null;
    });

    Future openDialog(WidgetTester tester) async {
      await pumpWrapped(
          tester,
          Builder(
              builder: (context) =>
                  TextButton(onPressed: () => editLiveFuelReport(context), child: const Text("open"))));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    testWidgets("pre-flight entry adds a fuel report", (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextFormField).first, "8.5");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(myTelemetry.fuelReportController.fuelReports.length, 1);
      expect(myTelemetry.fuelReportController.fuelReports.first.amount, 8.5);
    });

    testWidgets("submitting empty field leaves reports unchanged", (tester) async {
      myTelemetry.fuelReportController.insertFuelReport(minutes(1), 10);
      await openDialog(tester);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(myTelemetry.fuelReportController.fuelReports.length, 1);
      expect(myTelemetry.fuelReportController.fuelReports.first.amount, 10);
    });

    testWidgets("pre-flight hint shows the latest reported amount", (tester) async {
      myTelemetry.recordGeo = makeSamples();
      myTelemetry.fuelReportController.insertFuelReport(minutes(1), 10);
      myTelemetry.fuelReportController.insertFuelReport(minutes(10), 7.25);
      await openDialog(tester);

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.decoration?.hintText, contains(printValue(UnitType.fuel, 7.25)!));
    });

    testWidgets("shows average stats when the controller has a summary", (tester) async {
      myTelemetry.recordGeo = makeSamples();
      myTelemetry.fuelReportController.insertFuelReport(minutes(1), 10);
      myTelemetry.fuelReportController.insertFuelReport(minutes(10), 5);
      final stat = myTelemetry.fuelReportController.getSumFuelStat(myTelemetry.recordGeo)!;

      await openDialog(tester);

      expect(find.text("Avg"), findsOneWidget);
      expect(
          findRichTextContaining("${printValue(UnitType.fuel, stat.rate, decimals: 1)}$fuelRateStr"), findsOneWidget);
    });

    testWidgets("hides average stats with a single report", (tester) async {
      myTelemetry.recordGeo = makeSamples();
      myTelemetry.fuelReportController.insertFuelReport(minutes(1), 10);

      await openDialog(tester);

      expect(find.text("Avg"), findsNothing);
    });
  });
}
