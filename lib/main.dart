import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock/wakelock.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/flight_plan.dart';
import 'package:xcnav/providers/profile.dart';

// screens
import 'package:xcnav/screens/home.dart';
import 'package:xcnav/screens/loading.dart';

// Models
import 'package:xcnav/models/client.dart';

void main() {
  runApp(
    MultiProvider(providers: [
      ChangeNotifierProvider(create: (_) => MyTelemetry()),
      ChangeNotifierProvider(create: (_) => FlightPlan()),
      ChangeNotifierProvider(create: (_) => Profile()),
    ], child: const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    Wakelock.enable();

    Client client = Client(context);

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
      },
    );
  }
}
