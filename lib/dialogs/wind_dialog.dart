import 'dart:math';

import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';

import 'package:xcnav/settings_service.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/map_button.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';
import 'package:xcnav/widgets/wind_plot.dart';
import 'package:xcnav/widgets/wind_vector_plot.dart';

const valueStyle = TextStyle(fontSize: 40, color: Colors.white);
const unitStyle = TextStyle(fontSize: 18, color: Colors.grey);

class WindDialog extends StatefulWidget {
  const WindDialog({
    super.key,
  });
  @override
  State<WindDialog> createState() => _WindDialogState();
}

// These are here to preserve state between views
double? _airspeed;
double? _windspeed;
double? _windHdg;

class _WindDialogState extends State<WindDialog> with SingleTickerProviderStateMixin {
  static const List<Tab> myTabs = <Tab>[
    Tab(text: "Detector"),
    Tab(text: "Calculate"),
    Tab(text: "Route"),
  ];

  late TabController _tabController;
  late MapController mapController;

  // Calculated
  double plotScale = 1;
  Offset? craftVector;
  Offset? collectiveVector;

  ETA? routeETA;
  List<LatLng>? routePoints;
  bool mapReady = false;

  TextEditingController airSpeedController = TextEditingController(
      text: _airspeed != null ? unitConverters[UnitType.speed]!(_airspeed!).toStringAsFixed(0) : null);
  TextEditingController windSpeedController = TextEditingController(
      text: _windspeed != null ? unitConverters[UnitType.speed]!(_windspeed!).toStringAsFixed(0) : null);

  GlobalKey vectorBox = GlobalKey(debugLabel: "windVectorBox");

  ChangeNotifier newCalc = ChangeNotifier();
  ChangeNotifier newRoute = ChangeNotifier();

  final mapKey = GlobalKey(debugLabel: "windDialog_mapView");

  @override
  void initState() {
    super.initState();
    mapReady = false;
    mapController = MapController();
    _tabController = TabController(vsync: this, length: myTabs.length);

    if (!settingsMgr.rumOptOut.value) {
      DatadogSdk.instance.rum?.startView("/home/wind_dialog");
      DatadogSdk.instance.rum?.addAttribute("view_map_northLockWind", settingsMgr.northlockWind.value);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();

    if (!settingsMgr.rumOptOut.value) {
      DatadogSdk.instance.rum?.stopView("/home/wind_dialog");
    }
  }

  Offset calcCollective(Offset windVector, double airspeed) {
    double collectiveMag = 0;
    late Offset collective;
    final comp = airspeed * airspeed - windVector.dx * windVector.dx;
    if (comp >= 0) {
      collectiveMag = -sqrt(comp) + windVector.dy;
      collective = Offset(0, collectiveMag);
    }
    if (comp < 0 || collectiveMag > 0) {
      collectiveMag = sqrt(windVector.distance * windVector.distance - airspeed * airspeed);
      final inscribedTheta = asin(airspeed / windVector.distance);
      final collectiveTheta = windVector.direction + inscribedTheta * (windVector.dx < 0 ? 1 : -1);
      collective = Offset.fromDirection(collectiveTheta, collectiveMag);
    }
    return collective;
  }

  @override
  Widget build(BuildContext context) {
    /// unified getter
    final wind = Provider.of<Wind>(context, listen: false);
    double? getAirspeed() {
      return _airspeed ?? wind.result?.airspeed;
    }

    double? getWindspeed() {
      return _windspeed ?? wind.result?.windSpd;
    }

    double? getWindHdg() {
      return _windHdg ?? wind.result?.windHdg;
    }

    Offset? getWindVector() {
      if (getWindspeed() != null && getWindHdg() != null) {
        return Offset.fromDirection(getWindHdg()!, getWindspeed()!);
      } else {
        return null;
      }
    }

    /// Refresh the vector chart in "Calulate" Tab
    void refreshCalculation() {
      final tempWind = getWindspeed();
      final tempAir = getAirspeed();
      final tempWindVector = getWindVector();
      debugPrint("------------ refresh calc");
      if (tempWind != null && tempAir != null && tempWindVector != null) {
        collectiveVector = calcCollective(tempWindVector, tempAir);
        craftVector = collectiveVector! - tempWindVector;
        plotScale = (tempWind + tempAir) * 0.9;
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        newCalc.notifyListeners();
      } else {
        collectiveVector = null;
        craftVector = null;
      }
    }

    /// Refresh the map view in the "Route" tab
    void refreshRoute(List<LatLng>? points) {
      // final tempWind = getWindspeed();
      final tempAir = getAirspeed();
      final tempWindVector = getWindVector();
      debugPrint("------------ refresh route");

      if (points != null && tempWindVector != null && tempAir != null) {
        routeETA = ETA(0, Duration.zero);
        routePoints = [points.first];

        for (int t = 1; t < points.length; t++) {
          final originalDistance = latlngCalc.distance(points[t - 1], points[t]);
          final effectiveSpeed = calcCollective(
              Offset.fromDirection(
                  tempWindVector.direction - latlngCalc.bearing(routePoints!.last, points[t]) / 180 * pi,
                  tempWindVector.distance),
              tempAir);

          final newPoint = latlngCalc.offset(
              routePoints!.last,
              min(originalDistance, latlngCalc.distance(routePoints!.last, points[t])),
              latlngCalc.bearing(routePoints!.last, points[t]) + effectiveSpeed.direction * 180 / pi + 90);
          routeETA =
              routeETA! + ETA.fromSpeed(latlngCalc.distance(routePoints!.last, newPoint), effectiveSpeed.distance);

          routePoints!.add(newPoint);
        }
      } else {
        routeETA = null;
        routePoints = null;
      }

      if (mapReady && (mapKey.currentState?.mounted ?? false)) {
        mapController.fitBounds(padLatLngBounds(LatLngBounds.fromPoints((routePoints ?? []) + (points ?? [])), 0.1));
      } else {
        // Map was disposed and not ready yet
        mapReady = false;
      }
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      newRoute.notifyListeners();
    }

    return Dialog(
      insetPadding: const EdgeInsets.only(top: 100, left: 10, right: 10),
      alignment: Alignment.topCenter,
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          TabBar(
            controller: _tabController,
            tabs: myTabs,
            onTap: (value) {
              if (_tabController.index == 1) refreshCalculation();
              setState(() {});
            },
          ),
          [
            // ====================================================================================
            //
            // ---- Detector
            //
            // ====================================================================================
            Consumer<Wind>(builder: (context, wind, _) {
              return Row(mainAxisSize: MainAxisSize.max, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Icon(
                            Icons.flight,
                            size: 35,
                            color: Colors.red,
                          ),
                          Text.rich(wind.result != null
                              ? richValue(UnitType.speed, wind.result!.airspeed,
                                  digits: 3, valueStyle: valueStyle, unitStyle: unitStyle)
                              : const TextSpan(text: "?", style: valueStyle)),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Icon(Icons.air, size: 35, color: Colors.blue),
                          Text.rich(
                            wind.result != null
                                ? richValue(UnitType.speed, wind.result!.windSpd,
                                    digits: 3, valueStyle: valueStyle, unitStyle: unitStyle)
                                : const TextSpan(text: "?", style: valueStyle),
                          ),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ElevatedButton.icon(
                            onPressed: () {
                              if (wind.samples.length > 10) {
                                wind.samples.removeRange(0, wind.samples.length - 10);
                                wind.clearResult();
                              }
                              if (!settingsMgr.rumOptOut.value) {
                                DatadogSdk.instance.rum?.addUserAction(RumUserActionType.tap, "Reset Wind Detector");
                              }
                            },
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.red,
                            ),
                            label: const Text("Reset")),
                      )
                    ],
                  ),
                ),

                /// --- Wind Readings Polar Chart
                ValueListenableBuilder<bool>(
                    valueListenable: settingsMgr.northlockWind.listenable,
                    builder: (context, northlockWind, _) {
                      return Card(
                          color: Colors.black26,
                          child: SizedBox(
                              width: MediaQuery.of(context).size.width - 180,
                              child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Stack(fit: StackFit.expand, children: [
                                    wind.result == null
                                        ? const Center(
                                            child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Padding(
                                                padding: EdgeInsets.all(10.0),
                                                child: Text("Slowly Turn ¼ Circle", style: TextStyle(fontSize: 18)),
                                              ),
                                              CircularProgressIndicator.adaptive(
                                                strokeWidth: 3,
                                              )
                                            ],
                                          ))
                                        : ClipRect(
                                            child: CustomPaint(
                                              painter: WindPlotPainter(
                                                  3,
                                                  wind.result!.samplesX,
                                                  wind.result!.samplesY,
                                                  wind.result!.maxSpd * 1.1,
                                                  wind.result!.circleCenter,
                                                  wind.result!.airspeed,
                                                  northlockWind),
                                            ),
                                          ),
                                    Positioned(
                                        left: 4,
                                        top: 4,
                                        child: MapButton(
                                            size: 40,
                                            onPressed: () {
                                              settingsMgr.northlockWind.value = !northlockWind;
                                              if (!settingsMgr.rumOptOut.value) {
                                                DatadogSdk.instance.rum?.addAttribute(
                                                    "view_map_northLockWind", settingsMgr.northlockWind.value);
                                              }
                                            },
                                            selected: false,
                                            child: Container(
                                              width: 40,
                                              height: 40,
                                              transformAlignment: const Alignment(0, 0),
                                              transform: Matrix4.rotationZ(northlockWind
                                                  ? 0
                                                  : (wind.samples.isEmpty ? 0 : -wind.samples.last.hdg)),
                                              child: northlockWind
                                                  ? SvgPicture.asset(
                                                      "assets/images/compass_north.svg",
                                                      // fit: BoxFit.none,
                                                      color: Colors.white,
                                                    )
                                                  : Transform.scale(
                                                      scale: 1.4,
                                                      child: SvgPicture.asset(
                                                        "assets/images/compass.svg",
                                                        // fit: BoxFit.none,
                                                      ),
                                                    ),
                                            )))
                                  ]))));
                    })
              ]);
            }),

            // ====================================================================================
            //
            // ---- CALCULATE
            //
            // ====================================================================================
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // LEFT SIDE
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // --- Airspeed
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.flight,
                              size: 35,
                              color: Colors.red,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              onTap: () => airSpeedController.clear(),
                              controller: airSpeedController,
                              textAlign: TextAlign.center,
                              autofocus: airSpeedController.text.isEmpty,
                              decoration: InputDecoration(
                                  suffixText: getUnitStr(UnitType.speed),
                                  hintText: wind.result?.airspeed != null
                                      ? unitConverters[UnitType.speed]!(getAirspeed()!).toStringAsFixed(1)
                                      : null,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.all(4)),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]'))],
                              onChanged: (value) {
                                if (value.isNotEmpty) {
                                  _airspeed = (parseAsDouble(value) ?? 0) / unitConverters[UnitType.speed]!(1);
                                } else {
                                  _airspeed = null;
                                }
                                refreshCalculation();
                              },
                            ),
                          )
                        ]),
                      ),

                      // --- Wind Speed
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.air, size: 35, color: Colors.blue),
                          ),
                          Expanded(
                            child: TextField(
                              onTap: () => windSpeedController.clear(),
                              controller: windSpeedController,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                  suffixText: getUnitStr(UnitType.speed),
                                  hintText: wind.result?.windSpd != null
                                      ? unitConverters[UnitType.speed]!(getWindspeed()!).toStringAsFixed(1)
                                      : null,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.all(4)),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]'))],
                              onChanged: (value) {
                                if (value.isNotEmpty) {
                                  _windspeed = (parseAsDouble(value) ?? 0) / unitConverters[UnitType.speed]!(1);
                                } else {
                                  _windspeed = null;
                                }
                                debugPrint("Set Windspeed $_windspeed");
                                refreshCalculation();
                              },
                            ),
                          )
                        ]),
                      ),

                      // --- Ground Speed

                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          "Ground Speed",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
                        child: ListenableBuilder(
                            listenable: newCalc,
                            builder: (context, _) {
                              return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(Icons.speed, size: 35, color: Colors.amber),
                                ),
                                (collectiveVector != null)
                                    ? Text.rich(richValue(UnitType.speed,
                                        collectiveVector!.distance * (collectiveVector!.dy > 0 ? -1 : 1),
                                        digits: 3, valueStyle: valueStyle, unitStyle: unitStyle))
                                    : const Text(
                                        "?",
                                        style: valueStyle,
                                      ),
                              ]);
                            }),
                      ),

                      // --- Warn drifting
                      ListenableBuilder(
                          listenable: newCalc,
                          builder: (context, _) {
                            if (collectiveVector != null && collectiveVector!.dx.abs() > 0.01) {
                              // DRIFTING!
                              return Padding(
                                  padding: const EdgeInsets.only(left: 8, right: 8),
                                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Icon(Icons.warning_amber_rounded, size: 35, color: Colors.amber),
                                    ),
                                    Text.rich(
                                      TextSpan(children: [
                                        const TextSpan(text: "Drifting "),
                                        TextSpan(
                                            text: ((collectiveVector!.direction + pi / 2) * 180 / pi)
                                                .abs()
                                                .round()
                                                .toStringAsFixed(0)),
                                        const TextSpan(text: " deg")
                                      ]),
                                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                    ),
                                  ]));
                            } else {
                              return Container();
                            }
                          }),
                    ],
                  ),
                ),

                /// RIGHT SIDE
                Container(
                    key: vectorBox,
                    child: Listener(
                        onPointerMove: (event) {
                          final size = vectorBox.currentContext?.size;
                          final delta = -event.localPosition + Offset(size?.width ?? 100, size?.height ?? 100) / 2;
                          _windHdg = delta.direction;
                          refreshCalculation();
                        },
                        child: Card(
                          color: Colors.black26,
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width - 180,
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: ClipRect(
                                  child: ListenableBuilder(
                                      listenable: newCalc,
                                      builder: (context, _) {
                                        final tempWindVector = getWindVector();

                                        if (tempWindVector != null && craftVector != null && collectiveVector != null) {
                                          return CustomPaint(
                                              painter: WindVectorPlotPainter(
                                            strokeWidth: 3,
                                            wind: tempWindVector / plotScale,
                                            craft: craftVector! / plotScale,
                                            collective: collectiveVector! / plotScale,
                                          ));
                                        } else {
                                          return const Align(
                                              alignment: Alignment.center,
                                              child: Icon(
                                                Icons.touch_app,
                                                size: 60,
                                                color: Colors.white,
                                              ));
                                        }
                                      })),
                            ),
                          ),
                        )))
              ],
            ),

            // ====================================================================================
            //
            // ---- ROUTE
            //
            // ====================================================================================
            Builder(builder: (context) {
              final activePlan = Provider.of<ActivePlan>(context, listen: false);
              final points = (activePlan.mapMeasurement == null || activePlan.mapMeasurement!.isEmpty
                      ? null
                      : activePlan.mapMeasurement) ??
                  (activePlan.selectedWp != null
                      ? activePlan
                          .buildNextWpIndicator(Provider.of<MyTelemetry>(context, listen: false).geo!, 10000,
                              baseTiles: MapTileSrc.topo)
                          .first
                          .points
                      : null);

              if (points?.isEmpty ?? true) {
                return const SizedBox(
                    height: 200, child: Center(child: Text("Make a measurement on the map,\nor select a waypoint.")));
              } else {
                return Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // LEFT SIDE
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // --- Airspeed
                          Padding(
                            padding: const EdgeInsets.only(left: 8, right: 8),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.flight,
                                  size: 35,
                                  color: Colors.red,
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  onTap: () => airSpeedController.clear(),
                                  controller: airSpeedController,
                                  textAlign: TextAlign.center,
                                  autofocus: airSpeedController.text.isEmpty,
                                  decoration: InputDecoration(
                                      suffixText: getUnitStr(UnitType.speed),
                                      hintText: wind.result?.airspeed != null
                                          ? unitConverters[UnitType.speed]!(getAirspeed()!).toStringAsFixed(1)
                                          : null,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      contentPadding: const EdgeInsets.all(4)),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]'))],
                                  onChanged: (value) {
                                    if (value.isNotEmpty) {
                                      _airspeed = (parseAsDouble(value) ?? 0) / unitConverters[UnitType.speed]!(1);
                                    } else {
                                      _airspeed = null;
                                    }
                                    refreshRoute(points!);
                                  },
                                ),
                              )
                            ]),
                          ),

                          // --- Wind Speed
                          Padding(
                            padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(Icons.air, size: 35, color: Colors.blue),
                              ),
                              Expanded(
                                child: TextField(
                                  onTap: () => windSpeedController.clear(),
                                  controller: windSpeedController,
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                      suffixText: getUnitStr(UnitType.speed),
                                      hintText: wind.result?.windSpd != null
                                          ? unitConverters[UnitType.speed]!(getWindspeed()!).toStringAsFixed(1)
                                          : null,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      contentPadding: const EdgeInsets.all(4)),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]'))],
                                  onChanged: (value) {
                                    if (value.isNotEmpty) {
                                      _windspeed = (parseAsDouble(value) ?? 0) / unitConverters[UnitType.speed]!(1);
                                    } else {
                                      _windspeed = null;
                                    }
                                    refreshRoute(points!);
                                  },
                                ),
                              )
                            ]),
                          ),

                          // --- Calculations
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                              "ETA with Wind",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),

                          ListenableBuilder(
                              listenable: newRoute,
                              builder: (context, _) {
                                if (routeETA != null && routeETA!.time != null) {
                                  return Column(
                                    children: [
                                      Padding(
                                          padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
                                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                            const Padding(
                                              padding: EdgeInsets.only(right: 8),
                                              child: Icon(Icons.speed, size: 30, color: Colors.amber),
                                            ),
                                            Text.rich(richValue(UnitType.speed, routeETA!.speed!,
                                                digits: 3, valueStyle: valueStyle, unitStyle: unitStyle)),
                                          ])),
                                      Padding(
                                          padding: const EdgeInsets.only(left: 8, right: 8),
                                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                            const Padding(
                                              padding: EdgeInsets.only(right: 8),
                                              child: Icon(Icons.alarm, size: 30, color: Colors.amber),
                                            ),
                                            Text.rich(richHrMin(
                                                duration: routeETA!.time,
                                                valueStyle:
                                                    valueStyle.merge(TextStyle(fontSize: valueStyle.fontSize! - 8)),
                                                unitStyle:
                                                    unitStyle.merge(TextStyle(fontSize: unitStyle.fontSize! - 3)))),
                                          ])),
                                    ],
                                  );
                                } else {
                                  return const Padding(
                                      padding: EdgeInsets.only(left: 8, right: 8),
                                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                        Padding(
                                          padding: EdgeInsets.only(right: 8),
                                          child: Icon(Icons.warning_amber_rounded, size: 35, color: Colors.amber),
                                        ),
                                        Text(
                                          "No Arrival",
                                          style:
                                              TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 20),
                                        ),
                                      ]));
                                }
                              }),
                        ],
                      ),
                    ),

                    /// RIGHT SIDE
                    Container(
                        key: vectorBox,
                        child: Listener(
                            onPointerMove: (event) {
                              final size = vectorBox.currentContext?.size;
                              final delta = -event.localPosition + Offset(size?.width ?? 100, size?.height ?? 100) / 2;
                              _windHdg = delta.direction;
                              refreshRoute(points);
                            },
                            child: Card(
                                color: Colors.black26,
                                child: SizedBox(
                                    width: MediaQuery.of(context).size.width - 180,
                                    child: AspectRatio(
                                        aspectRatio: 1,
                                        child: ClipRRect(
                                            borderRadius: BorderRadius.circular(5),
                                            child: ListenableBuilder(
                                                listenable: newRoute,
                                                builder: (context, _) {
                                                  final selectedWp = activePlan.getSelectedWp();
                                                  return Stack(
                                                    children: [
                                                      FlutterMap(
                                                        key: mapKey,
                                                        mapController: mapController,
                                                        options: MapOptions(
                                                            onMapReady: () {
                                                              mapReady = true;
                                                              refreshRoute(points);
                                                            },
                                                            bounds: padLatLngBounds(
                                                                LatLngBounds.fromPoints(
                                                                    (routePoints ?? []) + (points ?? [])),
                                                                0.1),
                                                            interactiveFlags: InteractiveFlag.none),
                                                        children: [
                                                          getMapTileLayer(MapTileSrc.topo),

                                                          // Next waypoint: path
                                                          if (selectedWp != null &&
                                                              !selectedWp.isPath) // Waypoint markers
                                                            MarkerLayer(markers: [
                                                              Marker(
                                                                  point: selectedWp.latlng[0],
                                                                  height: 60 * 0.8,
                                                                  width: 40 * 0.8,
                                                                  rotate: true,
                                                                  anchorPos: AnchorPos.exactly(Anchor(20 * 0.8, 0)),
                                                                  rotateOrigin: const Offset(0, 30 * 0.8),
                                                                  builder: (context) =>
                                                                      WaypointMarker(selectedWp, 60 * 0.8))
                                                            ]),
                                                          // Next waypoint: marker
                                                          if (selectedWp != null &&
                                                              selectedWp.isPath) // Waypoints: paths
                                                            PolylineLayer(polylines: [
                                                              Polyline(
                                                                  points: selectedWp.latlng,
                                                                  strokeWidth: 6.0,
                                                                  color: selectedWp.getColor())
                                                            ]),

                                                          if (activePlan.mapMeasurement != null &&
                                                              activePlan.mapMeasurement!.isNotEmpty)
                                                            PolylineLayer(polylines: [
                                                              Polyline(
                                                                  points: activePlan.mapMeasurement!,
                                                                  strokeWidth: 6.0,
                                                                  color: Colors.orange)
                                                            ]),

                                                          if (routePoints != null)
                                                            PolylineLayer(
                                                              polylines: [
                                                                Polyline(
                                                                    points: routePoints!,
                                                                    color: const Color.fromARGB(180, 255, 255, 0),
                                                                    strokeWidth: 12),
                                                                Polyline(
                                                                    points: routePoints!,
                                                                    color: Colors.black,
                                                                    isDotted: true,
                                                                    strokeWidth: 4),
                                                              ],
                                                            ),
                                                        ],
                                                      ),
                                                      if (getWindHdg() != null)
                                                        Center(
                                                            child: Container(
                                                          transformAlignment: const Alignment(0, 0),
                                                          transform: Matrix4.rotationZ(getWindHdg()! + pi / 2),
                                                          child: SvgPicture.asset(
                                                            "assets/images/wind_sock.svg",
                                                            width: 60,
                                                            height: 60,
                                                          ),
                                                        )),
                                                      if (getWindHdg() == null)
                                                        const Align(
                                                            alignment: Alignment.center,
                                                            child: Icon(
                                                              Icons.touch_app,
                                                              size: 60,
                                                              color: Colors.black,
                                                            ))
                                                    ],
                                                  );
                                                })))))))
                  ],
                );
              }
            }),
          ][_tabController.index],
        ],
      ),
    );
  }
}
