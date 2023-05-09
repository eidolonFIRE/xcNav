import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
// ignore: depend_on_referenced_packages
import 'package:provider/provider.dart';
import 'package:xcnav/check_permissions.dart';
import 'package:xcnav/endpoint.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/settings_service.dart';

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

// TODO: clean these
TextStyle instrLower = const TextStyle(fontSize: 35);
TextStyle instrUpper = const TextStyle(fontSize: 40);
TextStyle instrLabel = TextStyle(fontSize: 14, color: Colors.grey.shade400, fontStyle: FontStyle.italic);

class _MyHomePageState extends State<MyHomePage> {
  final viewMapKey = GlobalKey<ViewMapState>();

  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey(debugLabel: "MainScaffold");

  PageController viewController = PageController(initialPage: 0);
  int viewPageIndex = 1;
  final pageIndexNames = ["Menu", "Map", "Side", "Points", "Chat"];

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

    Provider.of<MyTelemetry>(context, listen: false).addListener(() {
      if (viewMapKey.currentState?.mapReady ?? false) {
        if (viewMapKey.currentState?.isDragging ?? false) {
          // Update skipped because user is dragging something on the map
        } else {
          viewMapKey.currentState?.refreshMapView();
        }
      }
    });
  }

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
                    ValueListenableBuilder(
                        valueListenable: settingsMgr.groundModeTelem.listenable,
                        builder: (context, value, _) {
                          return Switch.adaptive(
                              value: value as bool, onChanged: (value) => settingsMgr.groundModeTelem.value = value);
                        }),
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

    checkPermissions(context).then((failed) {
      final myTelemetry = Provider.of<MyTelemetry>(context, listen: false);
      if (failed == false && !myTelemetry.isInitialized) {
        // get initial location
        debugPrint("Getting initial location from GPS");
        final myTelemetry = Provider.of<MyTelemetry>(context, listen: false);
        GeolocatorPlatform.instance.getCurrentPosition().then((location) {
          debugPrint("initial location: $location");
          myTelemetry.updateGeo(location);
          myTelemetry.init();

          // Setup the backend
          selectEndpoint(LatLng(location.latitude, location.longitude));
        });
      }
    });

    if (pageIndexNames[viewPageIndex] == "Chat") {
      // Don't notify
      Provider.of<ChatMessages>(context, listen: false).markAllRead(false);
    }

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        key: scaffoldKey,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leadingWidth: 35,
          toolbarHeight: 90,
          title: settingsMgr.groundMode.value ? groundControlBar(context) : topInstruments(context),
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
              type: BottomNavigationBarType.fixed,
              showUnselectedLabels: false,
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
                debugPrint("BottomNavigationBar.tap($value)");
                if (value == 0) {
                  scaffoldKey.currentState?.openDrawer();
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
