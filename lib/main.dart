import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:wakelock/wakelock.dart';
// import 'dart:math' as math;
import 'dart:async';
import 'package:collection/collection.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/flight_plan.dart';
import 'package:xcnav/util/geo.dart';

// widgets
import 'package:xcnav/widgets/top_instrument.dart';
import 'package:xcnav/widgets/waypoint_card.dart';

// screens
import 'package:xcnav/screens/home.dart';
import 'package:xcnav/screens/loading.dart';


void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MyTelemetry()),
        ChangeNotifierProvider(create: (_) => FlightPlan()),
      ],
      child: const MyApp()
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    Wakelock.enable();

    return MaterialApp(
      title: 'xcNav',
      theme: ThemeData(
        fontFamily: "roboto-condensed",

        // primaryColor: Color.fromRGBO(48, 57, 68, 1),
        // primaryColorLight: Color.fromRGBO(48, 57, 68, 1),
        primarySwatch: Colors.blueGrey,
        brightness: Brightness.dark,
        primaryColorBrightness: Brightness.dark,
        textTheme: const TextTheme(
          button: TextStyle(
            fontSize: 30,
            color: Colors.white,
          )
        ),
        // textButtonTheme: TextButtonThemeData(
        //   style: ButtonStyle(
        //       textStyle: MaterialStateProperty.resolveWith((state) => const TextStyle(color: Colors.white),
        //     ),
        //   )
        // )
      ),

      initialRoute: "/",
      routes: {
        "/": (context) => const LoadingScreen(),
        "/home": (context) => MyHomePage(initialLocation: LatLng(37.4, -122))
      },
    );
  }
}
