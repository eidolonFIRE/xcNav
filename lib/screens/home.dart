import 'package:flutter/material.dart';
import 'package:feature_discovery/feature_discovery.dart';
// ignore: depend_on_referenced_packages
import 'package:provider/provider.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/settings.dart';

// Views
import 'package:xcnav/views/view_chat.dart';
import 'package:xcnav/views/view_elevation.dart';
import 'package:xcnav/views/view_map.dart';
import 'package:xcnav/views/view_waypoints.dart';

// widgets
import 'package:xcnav/widgets/top_instruments.dart';
import 'package:xcnav/widgets/main_menu.dart';

// misc
import 'package:xcnav/util.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

TextStyle instrLower = const TextStyle(fontSize: 35);
TextStyle instrUpper = const TextStyle(fontSize: 40);
TextStyle instrLabel = TextStyle(fontSize: 14, color: Colors.grey.shade400, fontStyle: FontStyle.italic);

class _MyHomePageState extends State<MyHomePage> {
  final viewMapKey = GlobalKey<ViewMapState>();

  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey();

  PageController viewController = PageController(initialPage: 0);
  int viewPageIndex = 1;

  final features = [
    "focusOnMe",
    "focusOnGroup",
    "instruments",
    "flightPlan",
    "qrScanner",
  ];

  @override
  _MyHomePageState();

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    showFeatures();

    Provider.of<MyTelemetry>(context, listen: false).addListener(() {
      if (viewMapKey.currentState?.mapReady ?? false) {
        viewMapKey.currentState?.refreshMapView();
      }
    });
  }

  void showFeatures() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      FeatureDiscovery.discoverFeatures(context, features);
    });
  }

  // void showFlightPlan() {
  //   showModalBottomSheet(
  //       context: context,
  //       elevation: 0,
  //       // constraints: const BoxConstraints(maxHeight: 500),
  //       builder: (BuildContext context) {
  //         return SafeArea(
  //           child: Dismissible(
  //             key: const Key("flightPlanDrawer"),
  //             direction: DismissDirection.down,
  //             resizeDuration: const Duration(milliseconds: 10),
  //             onDismissed: (event) => Navigator.pop(context),
  //             child: flightPlanDrawer(setFocusMode, () {
  //               // onNewPath
  //               editablePolyline.points.clear();
  //               Navigator.popUntil(context, ModalRoute.withName("/home"));
  //               setFocusMode(FocusMode.addPath);
  //             }, (int index) {
  //               // onEditPointsCallback
  //               debugPrint("Editing Index $index");
  //               editingIndex = index;
  //               editablePolyline.points.clear();
  //               editablePolyline.points.addAll(Provider.of<ActivePlan>(context, listen: false).waypoints[index].latlng);
  //               Navigator.popUntil(context, ModalRoute.withName("/home"));
  //               setFocusMode(FocusMode.editPath);
  //             }),
  //           ),
  //         );
  //       });
  // }

  /// Top Bar in ground support mode
  Widget groundControlBar(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Text("Ground Support", style: instrLabel),
          Card(
              color: Colors.grey.shade700,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Share Position"),
                    Switch(
                        value: Provider.of<Settings>(context).groundModeTelemetry,
                        onChanged: (value) =>
                            Provider.of<Settings>(context, listen: false).groundModeTelemetry = value),
                  ],
                ),
              ))
        ],
      ),
    );
  }

  ///////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //
  // Main Build
  //
  //
  ///////////////////////////////////////////////////////////////////////////////////////////////////////
  @override
  Widget build(BuildContext context) {
    debugPrint("Build /home");
    setSystemUI();
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        key: scaffoldKey,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leadingWidth: 35,
          toolbarHeight: 90,
          title: Provider.of<Settings>(context).groundMode ? groundControlBar(context) : topInstruments(context),
          // actions: [IconButton(onPressed: () {}, icon: Icon(Icons.timer_outlined))],
        ),
        // --- Main Menu
        drawer: const MainMenu(),

        /// --- Main screen
        body: Column(
          children: [
            Expanded(
              child: PageView(
                controller: viewController,
                physics: const NeverScrollableScrollPhysics(),
                children: [ViewMap(key: viewMapKey), const ViewElevation(), const ViewWaypoints(), const ViewChat()],
              ),
            ),
            BottomNavigationBar(
              showSelectedLabels: false,
              unselectedItemColor: Colors.white54,
              selectedItemColor: Colors.white,
              iconSize: 35,
              currentIndex: viewPageIndex,
              selectedIconTheme: const IconThemeData(size: 40, shadows: [
                Shadow(blurRadius: 40, color: Colors.black, offset: Offset(0, 5)),
                Shadow(blurRadius: 60, color: Colors.black)
              ]),
              onTap: ((value) {
                if (value == 0) {
                  scaffoldKey.currentState?.openDrawer();
                  // Scaffold.of(context).openDrawer();
                } else {
                  setState(() {
                    viewPageIndex = value;
                    viewController.jumpToPage(value - 1);
                  });
                }
                if (value != 4) {
                  FocusScopeNode currentFocus = FocusScope.of(context);

                  if (!currentFocus.hasPrimaryFocus) {
                    currentFocus.unfocus();
                  }
                }
              }),
              items: [
                const BottomNavigationBarItem(
                  label: "Menu",
                  icon: Icon(
                    Icons.more_vert,
                  ),
                ),
                const BottomNavigationBarItem(
                  label: "Map",
                  icon: Icon(
                    Icons.map,
                  ),
                ),
                const BottomNavigationBarItem(
                  label: "Side",
                  icon: Icon(
                    Icons.area_chart,
                  ),
                ),
                const BottomNavigationBarItem(
                  label: "Points",
                  icon: Icon(
                    Icons.pin_drop,
                  ),
                ),
                BottomNavigationBarItem(
                  label: "Chat",
                  icon: Stack(
                    children: [
                      const Icon(
                        Icons.chat,
                      ),
                      if (Provider.of<ChatMessages>(context).numUnread > 0)
                        Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                                decoration: const BoxDecoration(
                                    color: Colors.red, borderRadius: BorderRadius.all(Radius.circular(10))),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Text(
                                    "${Provider.of<ChatMessages>(context).numUnread}",
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ))),
                    ],
                  ),
                ),
              ],
            )
          ],
        ),

        // --- Bottom Navigation Bar
      ),
    );
  }
}
