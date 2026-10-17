import 'dart:math';

import 'package:clock/clock.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/datadog.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/models/map_shapes.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';

import 'package:xcnav/settings_service.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/views/map/map_layers.dart';
import 'package:xcnav/views/map/map_markers.dart';
import 'package:xcnav/widgets/map_button.dart';
import 'package:xcnav/widgets/static_map.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';
import 'package:xcnav/widgets/wind_plot.dart';

const valueStyle = TextStyle(fontSize: 40, color: Colors.white);
const unitStyle = TextStyle(fontSize: 18, color: Colors.grey);

class WindDialog extends StatefulWidget {
  /// When set, the contents are built inline (no [Dialog] wrapper), sized to fit the parent,
  /// and a close button calls this.
  final VoidCallback? onClose;

  const WindDialog({
    super.key,
    this.onClose,
  });
  @override
  State<WindDialog> createState() => _WindDialogState();
}

class _WindDialogState extends State<WindDialog> with SingleTickerProviderStateMixin {
  static List<Tab> myTabs = <Tab>[
    Tab(text: "Detector".tr()),
    Tab(text: "Route".tr()),
  ];

  late TabController _tabController;

  ETA? routeETA;
  List<LatLng>? routePoints;

  double? _airspeed;
  double? _windspeed;
  double? _windHdg;

  TextEditingController airSpeedController = TextEditingController();
  TextEditingController windSpeedController = TextEditingController();

  GlobalKey vectorBox = GlobalKey(debugLabel: "windVectorBox");

  ChangeNotifier newRoute = ChangeNotifier();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(vsync: this, length: myTabs.length);

    startView("/home/wind_dialog");
    addAttribute("view_map_northLockWind", settingsMgr.northlockWind.value);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();

    stopView("/home/wind_dialog");
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

    airSpeedController.text = printValue(UnitType.speed, _airspeed, decimals: 1) ?? "";
    windSpeedController.text = printValue(UnitType.speed, _windspeed, decimals: 1) ?? "";

    /// Refresh the map view in the "Route" tab
    void refreshRoute(List<LatLng>? points) {
      // final tempWind = getWindspeed();
      final tempAir = getAirspeed();
      final tempWindVector = getWindVector();

      if (points != null && tempWindVector != null && tempAir != null) {
        routeETA = ETA(0, Duration.zero);
        routePoints = [points.first];

        for (int t = 1; t < points.length; t++) {
          final originalDistance = latlngCalc.distance(points[t - 1], points[t]);
          final effectiveSpeed = calcCollective(
              Offset.fromDirection(
                  tempWindVector.direction - latlngCalc.bearing(routePoints!.last, points[t]) / 180 * pi - pi / 2,
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

      // (The route map fits itself to the new route when it rebuilds)
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      newRoute.notifyListeners();
    }

    final embedded = widget.onClose != null;

    final tabBar = TabBar(
      controller: _tabController,
      tabs: myTabs,
      onTap: (value) {
        setState(() {});
      },
    );

    Widget buildContent(double chartSize) => ListView(
          shrinkWrap: !embedded,
          physics: embedded ? null : const NeverScrollableScrollPhysics(),
          children: [
            embedded
                ? Row(children: [
                    Expanded(child: tabBar),
                    IconButton(
                        key: const Key("windDialog_close"), icon: const Icon(Icons.close), onPressed: widget.onClose),
                  ])
                : tabBar,
            [
              // ====================================================================================
              //
              // ---- Detector
              //
              // ====================================================================================
              Consumer<Wind>(builder: (context, wind, _) {
                return Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
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
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: ElevatedButton.icon(
                                  onPressed: () {
                                    if (wind.samples.length > 10) {
                                      wind.samples.removeRange(0, wind.samples.length - 10);
                                      wind.clearResult();
                                    }
                                    addTapAction("Reset Wind Detector".tr());
                                  },
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.red,
                                  ),
                                  label: Text("btn.Reset".tr())),
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
                                    width: chartSize,
                                    child: AspectRatio(
                                        aspectRatio: 1,
                                        child: Stack(fit: StackFit.expand, children: [
                                          wind.result == null
                                              ? Center(
                                                  child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Padding(
                                                      padding: EdgeInsets.all(10.0),
                                                      child: Text("Slowly Turn ¼ Circle".tr(),
                                                          style: TextStyle(fontSize: 18)),
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
                                                    addAttribute(
                                                        "view_map_northLockWind", settingsMgr.northlockWind.value);
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
                                                            colorFilter:
                                                                const ColorFilter.mode(Colors.white, BlendMode.srcIn),
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
                            .buildNextWpIndicator(myTelemetry.geo!, 10000, baseTiles: MapTileSrc.topo)
                            .first
                            .points
                        : null);

                if (points?.isEmpty ?? true) {
                  return SizedBox(height: 200, child: Center(child: Text("make_a_measurement".tr())));
                } else {
                  // Work out the route for the current wind once this tab is up
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) refreshRoute(points);
                  });
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
                                    onTap: () {
                                      airSpeedController.clear();
                                      refreshRoute(points);
                                    },
                                    controller: airSpeedController,
                                    textAlign: TextAlign.center,
                                    autofocus: airSpeedController.text.isEmpty,
                                    decoration: InputDecoration(
                                        suffixText: getUnitStr(UnitType.speed),
                                        hintText: printValue(UnitType.speed, getAirspeed(), decimals: 1),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.all(4)),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]'))],
                                    onChanged: (value) {
                                      _airspeed = parseDoubleValue(UnitType.speed, value);
                                      refreshRoute(points);
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
                                    onTap: () {
                                      windSpeedController.clear();
                                      refreshRoute(points);
                                    },
                                    controller: windSpeedController,
                                    textAlign: TextAlign.center,
                                    decoration: InputDecoration(
                                        suffixText: getUnitStr(UnitType.speed),
                                        hintText: printValue(UnitType.speed, getWindspeed(), decimals: 1),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.all(4)),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]'))],
                                    onChanged: (value) {
                                      _windspeed = parseDoubleValue(UnitType.speed, value);
                                      refreshRoute(points);
                                    },
                                  ),
                                )
                              ]),
                            ),

                            // --- Calculations
                            Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text(
                                "ETA with Wind".tr(),
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
                                    return Padding(
                                        padding: EdgeInsets.only(left: 8, right: 8),
                                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                          Padding(
                                            padding: EdgeInsets.only(right: 8),
                                            child: Icon(Icons.warning_amber_rounded, size: 35, color: Colors.amber),
                                          ),
                                          Text(
                                            "No Arrival".tr(),
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
                                final delta =
                                    -event.localPosition + Offset(size?.width ?? 100, size?.height ?? 100) / 2;
                                _windHdg = delta.direction + pi / 2;
                                refreshRoute(points);
                              },
                              child: Card(
                                  color: Colors.black26,
                                  child: SizedBox(
                                      width: chartSize,
                                      child: AspectRatio(
                                          aspectRatio: 1,
                                          child: ClipRRect(
                                              borderRadius: BorderRadius.circular(5),
                                              child: ListenableBuilder(
                                                  listenable: newRoute,
                                                  builder: (context, _) {
                                                    final selectedWp = activePlan.getSelectedWp();
                                                    final fuelIntercept = (getAirspeed() != null &&
                                                            getWindHdg() != null &&
                                                            getWindspeed() != null &&
                                                            myTelemetry.fuelReportController
                                                                    .getSumFuelStat(myTelemetry.recordGeo) !=
                                                                null &&
                                                            routePoints != null)
                                                        ? interpolateWithWind(routePoints!, getAirspeed()!,
                                                            getWindHdg()!, getWindspeed()!,
                                                            duration: myTelemetry.fuelReportController
                                                                .getSumFuelStat(myTelemetry.recordGeo)!
                                                                .extrapolateEndurance(
                                                                    myTelemetry.fuelReportController.fuelReports.last,
                                                                    from: clock.now()))
                                                        : null;

                                                    return Stack(
                                                      children: [
                                                        StaticMap(
                                                          bounds: padLatLngBounds(
                                                              LatLngBounds.fromPoints(
                                                                  (routePoints ?? []) + (points ?? [])),
                                                              0.1),
                                                          padding: EdgeInsets.zero,
                                                          shapes: [
                                                            ShapeLayer("route", lines: [
                                                              // Next waypoint: path
                                                              if (selectedWp != null && selectedWp.isPath)
                                                                MapPolyline(
                                                                    points: selectedWp.latlng,
                                                                    width: 6.0,
                                                                    color: selectedWp.getColor()),
                                                              if (activePlan.mapMeasurement != null &&
                                                                  activePlan.mapMeasurement!.isNotEmpty)
                                                                MapPolyline(
                                                                    points: activePlan.mapMeasurement!,
                                                                    width: 6.0,
                                                                    color: Colors.orange),
                                                              if (routePoints != null)
                                                                MapPolyline(
                                                                    points: routePoints!,
                                                                    color: const Color.fromARGB(180, 255, 255, 0),
                                                                    width: 12),
                                                              if (routePoints != null)
                                                                MapPolyline(
                                                                    points: routePoints!,
                                                                    color: Colors.black,
                                                                    pattern: LinePattern.dotted,
                                                                    width: 4),
                                                            ]),
                                                          ],
                                                          children: [
                                                            // Next waypoint: marker
                                                            if (selectedWp != null && !selectedWp.isPath)
                                                              MarkerLayer(markers: [
                                                                MapMarker(
                                                                    point: selectedWp.latlng[0],
                                                                    height: 60 * 0.8,
                                                                    width: 40 * 0.8,
                                                                    alignment: Alignment.topCenter,
                                                                    child: WaypointMarker(selectedWp, 60 * 0.8))
                                                              ]),

                                                            // "ME" Live Location Marker
                                                            const MyLocationLayer(size: 25),

                                                            if (fuelIntercept != null)
                                                              MarkerLayer(
                                                                markers: [
                                                                  MapMarker(
                                                                    width: 40,
                                                                    height: 40,
                                                                    point: fuelIntercept.latlng,
                                                                    child: const FuelWarningIcon(size: 40),
                                                                  )
                                                                ],
                                                              )
                                                          ],
                                                        ),
                                                        if (getWindHdg() != null)
                                                          Center(
                                                              child: Container(
                                                            transformAlignment: const Alignment(0, 0),
                                                            transform: Matrix4.rotationZ(getWindHdg() ?? 0),
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
        );

    if (embedded) {
      // Leave room for the tab bar; chart is square
      return LayoutBuilder(
          builder: (context, constraints) =>
              buildContent(max(100, min(constraints.maxWidth - 180, constraints.maxHeight - 64))));
    }

    return Dialog(
      insetPadding: const EdgeInsets.only(top: 90),
      alignment: Alignment.topCenter,
      child: buildContent(MediaQuery.of(context).size.width - 180),
    );
  }
}
