import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock/wakelock.dart';
import 'package:focus_detector/focus_detector.dart';

// providers
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/screens/log_replay.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/weather.dart';
import 'package:xcnav/providers/wind.dart';

// screens
import 'package:xcnav/screens/adsb_help.dart';
import 'package:xcnav/screens/checklist_viewer.dart';
import 'package:xcnav/screens/home.dart';
import 'package:xcnav/screens/loading.dart';
import 'package:xcnav/screens/plan_editor.dart';
import 'package:xcnav/screens/profile_editor.dart';
import 'package:xcnav/screens/qr_scanner.dart';
import 'package:xcnav/screens/settings_editor.dart';
import 'package:xcnav/screens/flight_log_viewer.dart';
import 'package:xcnav/screens/plans_viewer.dart';
import 'package:xcnav/screens/group_details.dart';
import 'package:xcnav/screens/about.dart';
import 'package:xcnav/screens/weather_viewer.dart';

// Misc
import 'package:xcnav/notifications.dart';
import 'package:xcnav/tts_service.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/map_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  SharedPreferences.getInstance().then((prefs) {
    settingsMgr = SettingsMgr(prefs);
    initMapCache();
  }).then((value) {
    runApp(
      MultiProvider(
          providers: [
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
              create: (BuildContext context) => Client(context),
              lazy: false,
            )
          ],
          child: FocusDetector(
              onFocusGained: () => {setFocus(true)}, onFocusLost: () => {setFocus(false)}, child: const XCNav())),
    );
  });
}

class XCNav extends StatelessWidget {
  const XCNav({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Wakelock.enable();

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
      title: 'xcNav',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
          // Limit how big system text modifier can be
          data: MediaQuery.of(context).copyWith(textScaleFactor: min(1.5, MediaQuery.of(context).textScaleFactor)),
          child: child!),
      darkTheme: ThemeData(
        fontFamily: "roboto-condensed",
        // appBarTheme: AppBarTheme(backgroundColor: primaryDarkColor),
        // scaffoldBackgroundColor: Color.fromRGBO(48, 57, 68, 1),
        // primaryColorLight: primaryDarkColor,
        backgroundColor: darkColor,
        appBarTheme: const AppBarTheme(toolbarTextStyle: TextStyle(fontSize: 40), backgroundColor: darkColor),
        // primarySwatch: Colors.grey,
        // scaffoldBackgroundColor: Colors.blueGrey.shade900,
        brightness: Brightness.dark,
        bottomSheetTheme: const BottomSheetThemeData(backgroundColor: darkColor),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(backgroundColor: darkColor),
        textTheme: const TextTheme(
          headline4: TextStyle(color: Colors.white),
          bodyText1: TextStyle(fontSize: 20),
          // button: TextStyle(
          //   fontSize: 20,
          //   color: Colors.white,
          // )
        ),
        dialogTheme: DialogTheme(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            side: MaterialStateProperty.resolveWith<BorderSide>((states) => const BorderSide(color: Colors.black)),
            backgroundColor: MaterialStateProperty.resolveWith<Color>((states) => Colors.grey.shade900),
            minimumSize: MaterialStateProperty.resolveWith<Size>((states) => const Size(30, 40)),
            padding: MaterialStateProperty.resolveWith<EdgeInsetsGeometry>((states) => const EdgeInsets.all(12)),
            shape: MaterialStateProperty.resolveWith<OutlinedBorder>((_) {
              return RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
            }),
            textStyle: MaterialStateProperty.resolveWith<TextStyle>(
                (states) => const TextStyle(color: Colors.white, fontSize: 20)),
          ),

          // child: ElevatedButton(onPressed: () {}, child: Text('label')),
        ),
        popupMenuTheme: PopupMenuThemeData(textStyle: Theme.of(context).textTheme.bodyMedium),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: MaterialStateProperty.all(Colors.white),
            textStyle: MaterialStateProperty.resolveWith<TextStyle>(
                (states) => const TextStyle(color: Colors.white, fontSize: 20)),
          ),

          // child: ElevatedButton(onPressed: () {}, child: Text('label')),
        ),
        // navigationBarTheme: const NavigationBarThemeData(
        //   backgroundColor: darkColor,
        // )
        // textButtonTheme: TextButtonThemeData(
        //   style: ButtonStyle(
        //       textStyle: MaterialStateProperty.resolveWith((state) => const TextStyle(color: Colors.white),
        //     ),
        //   )
        // )
      ),
      themeMode: ThemeMode.dark,
      initialRoute: "/",
      routes: {
        "/": (context) => const LoadingScreen(),
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
      },
    );
  }
}
