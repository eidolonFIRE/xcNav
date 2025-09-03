import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_detector/focus_detector.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xcnav/datadog.dart';
import 'package:xcnav/locale.dart';

// providers
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/screens/ble_scan.dart';

// screens
import 'package:xcnav/screens/log_replay.dart';
import 'package:xcnav/screens/adsb_help.dart';
import 'package:xcnav/screens/checklist_viewer.dart';
import 'package:xcnav/screens/home.dart';
import 'package:xcnav/screens/plan_editor.dart';
import 'package:xcnav/screens/profile_editor.dart';
import 'package:xcnav/screens/qr_scanner.dart';
import 'package:xcnav/screens/servo_carb.dart';
import 'package:xcnav/screens/settings_editor.dart';
import 'package:xcnav/screens/flight_log_viewer.dart';
import 'package:xcnav/screens/plans_viewer.dart';
import 'package:xcnav/screens/group_details.dart';
import 'package:xcnav/screens/about.dart';
import 'package:xcnav/screens/weather_viewer.dart';

// Misc
import 'package:xcnav/notifications.dart';
import 'package:xcnav/servo_carb_service.dart';
import 'package:xcnav/tts_service.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/secrets.dart';
import 'package:xcnav/airports.dart';
import 'package:xcnav/util.dart';

LatLng lastKnownLatLng = const LatLng(37, -122);

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await EasyLocalization.ensureInitialized();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

    version = await PackageInfo.fromPlatform();

    final prefs = await SharedPreferences.getInstance();
    settingsMgr = SettingsMgr(prefs);
    initCarbNeedles(prefs);

    final configuration = DatadogConfiguration(
      clientToken: datadogToken,
      env: kDebugMode ? "debug" : "release",
      site: DatadogSite.us3,

      nativeCrashReportEnabled: true,
      // loggingConfiguration: DatadogLoggingConfiguration(
      //   loggerName: "xcNav: ${version.version}  -  ( build ${version.buildNumber} )",
      //   printLogsToConsole: true,
      // ),
      rumConfiguration: DatadogRumConfiguration(
        applicationId: datadogRumAppId,
        detectLongTasks: true,
      ),
    );

    await DatadogSdk.instance
        .initialize(configuration, settingsMgr.rumOptOut.value ? TrackingConsent.notGranted : TrackingConsent.granted);

    final ddsdk = DatadogSdk.instance;
    // ddsdk.sdkVerbosity = Verbosity.verbose;

    ddLogger = ddsdk.logs?.createLogger(DatadogLoggerConfiguration(
      name: "xcNav: ${version.version}  -  ( build ${version.buildNumber} )",
    ));

    // Set up an anonymous ID for logging and usage statistics.
    // This ID will be uncorrelated to any ID on the server and is therefore anonymous.
    // It will be saved, however, so individual clients can be distinguished.
    if (settingsMgr.datadogSdkId.value.isEmpty) {
      final random = Random.secure();
      final values = List<int>.generate(10, (i) => random.nextInt(255));
      settingsMgr.datadogSdkId.value = base64UrlEncode(values);
    }
    ddsdk.setUserInfo(id: settingsMgr.datadogSdkId.value);

    FlutterError.onError = (FlutterErrorDetails details) {
      error(details.toString(), errorStackTrace: details.stack);
      ddsdk.rum?.handleFlutterError(details);
      FlutterError.presentError(details);
    };

    // Let datadog know we will not be participating.
    if (settingsMgr.rumOptOut.value) {
      info("rum opt-out");
    }

    // Load last known LatLng
    final raw = prefs.getString("lastKnownLatLng");
    if (raw != null) {
      try {
        final data = jsonDecode(raw);
        lastKnownLatLng = LatLng(data["lat"] is int ? (data["lat"] as int).toDouble() : data["lat"],
            data["lng"] is int ? (data["lng"] as int).toDouble() : data["lng"]);
        debugPrint("Last known LatLng: ${lastKnownLatLng.toString()}");
      } catch (err, trace) {
        final msg = 'Parsing last known LatLng from "$raw"';
        error(msg, errorMessage: err.toString(), errorStackTrace: trace);
      }
    }
    await initMapCache();

    if (settingsMgr.rumOptOut.value) {
      addAttribute(settingsMgr.languageOverride.id, settingsMgr.languageOverride.value.toString());
    }
    debugPrint("Language in settings: ${settingsMgr.languageOverride.value}");

    runApp(EasyLocalization(
        supportedLocales: supportedLanguages.values.nonNulls.toList(),
        path: "assets/translations",
        fallbackLocale: Locale("en"),
        useFallbackTranslations: true,
        useFallbackTranslationsForEmptyResources: true,
        startLocale: supportedLanguages[settingsMgr.languageOverride.value],
        useOnlyLangCode: true,
        child: MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => MyTelemetry(),
                lazy: false,
              ),
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
                create: (BuildContext context) => Client(context),
                lazy: false,
              )
            ],
            child: FocusDetector(
                onFocusGained: () => {setFocus(true)}, onFocusLost: () => {setFocus(false)}, child: const XCNav()))));
  }, (e, s) {
    DatadogSdk.instance.rum?.addErrorInfo(e.toString(), RumErrorSource.source, stackTrace: s);
    throw e;
  });
}

class XCNav extends StatelessWidget {
  const XCNav({super.key});

  @override
  Widget build(BuildContext context) {
    DefaultAssetBundle.of(context).loadString("assets/airports.json").then((value) => loadAirports(value));

    WakelockPlus.enable();

    setSystemUI();

    configLocalNotification();

    ttsService = TtsService();

    Provider.of<MyTelemetry>(context, listen: false).globalContext = context;

    debugPrint("Building App");

    const darkColor = Color.fromARGB(255, 42, 42, 42);

    // --- Setup Audio Cue Service
    audioCueService = AudioCueService(
      ttsService: ttsService,
      group: Provider.of<Group>(context, listen: false),
      activePlan: Provider.of<ActivePlan>(context, listen: false),
    );

    final chatMessages = Provider.of<ChatMessages>(context, listen: false);
    chatMessages.addListener(() {
      if (chatMessages.messages.isNotEmpty &&
          chatMessages.messages.last.pilotId != Provider.of<Profile>(context, listen: false).id) {
        audioCueService.cueChatMessage(chatMessages.messages.last);
      }
    });

    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      navigatorObservers:
          settingsMgr.rumOptOut.value ? [] : [DatadogNavigationObserver(datadogSdk: DatadogSdk.instance)],
      title: 'xcNav',
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData(
        useMaterial3: false,
        fontFamily: "roboto-condensed",
        // appBarTheme: AppBarTheme(backgroundColor: primaryDarkColor),
        // scaffoldBackgroundColor: Color.fromRGBO(48, 57, 68, 1),
        // primaryColorLight: primaryDarkColor,

        colorScheme: const ColorScheme.dark(surface: darkColor, primary: Colors.lightBlue),
        appBarTheme: const AppBarTheme(toolbarTextStyle: TextStyle(fontSize: 40), backgroundColor: darkColor),

        textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 18),
            headlineLarge: TextStyle(color: Colors.white),
            headlineMedium: TextStyle(color: Colors.white)),
        dropdownMenuTheme: const DropdownMenuThemeData(textStyle: TextStyle(color: Colors.white)),

        brightness: Brightness.dark,
        bottomSheetTheme: const BottomSheetThemeData(backgroundColor: darkColor),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(backgroundColor: darkColor),
        dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith<Color>(
                (states) => states.contains(WidgetState.disabled) ? Colors.grey.shade600 : Colors.white),
            iconColor: WidgetStateProperty.resolveWith<Color>(
                (states) => states.contains(WidgetState.disabled) ? Colors.grey.shade600 : Colors.white),
            side: WidgetStateProperty.resolveWith<BorderSide>((states) => const BorderSide(color: Colors.black)),
            backgroundColor: WidgetStateProperty.resolveWith<Color>((states) => Colors.grey.shade900),
            minimumSize: WidgetStateProperty.resolveWith<Size>((states) => const Size(30, 40)),
            padding: WidgetStateProperty.resolveWith<EdgeInsetsGeometry>((states) => const EdgeInsets.all(12)),
            shape: WidgetStateProperty.resolveWith<OutlinedBorder>((_) {
              return RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
            }),
            textStyle: WidgetStateProperty.resolveWith<TextStyle>(
                (states) => const TextStyle(color: Colors.white, fontSize: 20)),
          ),
        ),
        toggleButtonsTheme: ToggleButtonsThemeData(
            borderRadius: BorderRadius.circular(10),
            selectedColor: Colors.white,
            selectedBorderColor: Colors.blue,
            fillColor: Colors.black54),
        popupMenuTheme: PopupMenuThemeData(
          textStyle: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(color: Colors.white)),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.all(Colors.white),
            textStyle: WidgetStateProperty.resolveWith<TextStyle>(
                (states) => const TextStyle(color: Colors.white, fontSize: 20)),
          ),
        ),
      ),
      themeMode: ThemeMode.dark,
      initialRoute: "/home",
      routes: {
        "/home": (context) => const MyHomePage(),
        "/profileEditor": (context) => const ProfileEditor(),
        "/qrScanner": (context) => const QRScanner(),
        "/settings": (context) => const SettingsEditor(),
        "/flightLogs": (context) => const FlightLogViewer(),
        "/plans": (context) => const PlansViewer(),
        "/planEditor": (context) => const PlanEditor(),
        "/groupDetails": (context) => const GroupDetails(),
        "/weather": (context) => const WeatherViewer(),
        "/about": (context) => const About(),
        "/adsbHelp": (context) => const ADSBhelp(),
        "/checklist": (context) => const ChecklistViewer(),
        "/logReplay": (context) => const LogReplay(),
        "/servoCarb": (context) => const ServoCarb(),
        "/bleScan": (context) => const ScanScreen(),
      },
    );
  }
}
