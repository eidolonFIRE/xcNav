import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock/wakelock.dart';

// providers
import 'package:xcnav/providers/client_state.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/flight_plan.dart';
import 'package:xcnav/providers/profile.dart';

// screens
import 'package:xcnav/screens/home.dart';
import 'package:xcnav/screens/loading.dart';
import 'package:xcnav/screens/party.dart';
import 'package:xcnav/screens/profile_editor.dart';
import 'package:xcnav/screens/qr_scanner.dart';

// Widgets
import 'package:xcnav/widgets/client.dart';

void main() {
  runApp(
    MultiProvider(providers: [
      ChangeNotifierProvider(create: (_) => ClientState()),
      ChangeNotifierProvider(create: (_) => MyTelemetry()),
      ChangeNotifierProvider(create: (_) => FlightPlan()),
      ChangeNotifierProvider(create: (_) => Profile()),
    ], child: const ClientWidget(child: MyApp())),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    Wakelock.enable();

    debugPrint("Building App");

    return MaterialApp(
      title: 'xcNav',
      darkTheme: ThemeData(
          fontFamily: "roboto-condensed",
          // appBarTheme: AppBarTheme(backgroundColor: primaryDarkColor),
          // scaffoldBackgroundColor: Color.fromRGBO(48, 57, 68, 1),
          // primaryColorLight: primaryDarkColor,
          // backgroundColor: primaryDarkColor,
          appBarTheme:
              const AppBarTheme(toolbarTextStyle: TextStyle(fontSize: 40)),
          primarySwatch: Colors.blueGrey,
          // scaffoldBackgroundColor: Colors.blueGrey[900],
          brightness: Brightness.dark,
          // primaryColorBrightness: Brightness.dark,
          // bottomSheetTheme:
          //     BottomSheetThemeData(backgroundColor: primaryDarkColor),
          // bottomNavigationBarTheme:
          //     BottomNavigationBarThemeData(backgroundColor: primaryDarkColor),
          textTheme: const TextTheme(
              button: TextStyle(
            fontSize: 30,
            color: Colors.white,
          )),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ButtonStyle(
              side: MaterialStateProperty.resolveWith<BorderSide>(
                  (states) => BorderSide(color: Colors.black)),
              backgroundColor: MaterialStateProperty.resolveWith<Color>(
                  (states) => Colors.black45),
              minimumSize: MaterialStateProperty.resolveWith<Size>(
                  (states) => Size(30, 40)),
              padding: MaterialStateProperty.resolveWith<EdgeInsetsGeometry>(
                  (states) => EdgeInsets.all(12)),
              // shape: MaterialStateProperty.resolveWith<OutlinedBorder>((_) {
              //   return RoundedRectangleBorder(
              //       borderRadius: BorderRadius.circular(20));
              // }),
              textStyle: MaterialStateProperty.resolveWith<TextStyle>(
                  (states) => TextStyle(color: Colors.white, fontSize: 24)),
            ),

            // child: ElevatedButton(onPressed: () {}, child: Text('label')),
          )
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
        "/party": (context) => const Party(),
        "/qrScanner": (context) => const QRScanner(),
      },
    );
  }
}
