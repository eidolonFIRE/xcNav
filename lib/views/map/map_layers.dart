import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/models/ga.dart';
import 'package:xcnav/models/tfr.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/tfr_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/weather_observation_service.dart';
import 'package:xcnav/widgets/pilot_marker.dart';

/// TFR polygons near [center].
class TfrLayer extends StatelessWidget {
  final LatLng center;

  const TfrLayer({super.key, required this.center});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TFR>?>(
        future: getTFRs(center),
        builder: (context, tfrsFuture) {
          if (tfrsFuture.hasData) {
            List<Polygon> polygons = [];

            for (final eachTfr in tfrsFuture.data!) {
              for (final shape in eachTfr.shapes) {
                final color = eachTfr.isActive(const Duration(hours: 3)) ? Colors.red : Colors.orange;
                polygons
                    .add(Polygon(points: shape, color: color.withAlpha(50), borderColor: color, borderStrokeWidth: 4));
              }
            }

            return PolygonLayer(
              polygons: polygons,
            );
          } else {
            return Container();
          }
        });
  }
}

/// Circle around me showing the ADSB proximity warning radius.
class AdsbProximityLayer extends StatelessWidget {
  const AdsbProximityLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: myTelemetry,
        builder: (context, _) {
          return CircleLayer(circles: [
            CircleMarker(
                point: myTelemetry.geo!.latlng,
                color: Colors.transparent,
                borderStrokeWidth: 1,
                borderColor: Colors.black54,
                radius: proximityProfileOptions[settingsMgr.adsbProximitySize.value]!.horizontalDist,
                useRadiusInMeter: true)
          ]);
        });
  }
}

/// Chevrons along the path to the selected waypoint.
class NextWaypointBarbsLayer extends StatelessWidget {
  final ActivePlan plan;

  const NextWaypointBarbsLayer({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: myTelemetry,
        builder: (context, _) {
          return MarkerLayer(
              markers: plan
                  .buildNextWpBarbs(myTelemetry.geo!,
                      (settingsMgr.displayUnitDist.value == DisplayUnitsDist.metric ? 1000 : 1609.344))
                  .map((e) => Marker(
                      point: e.latlng,
                      width: 20,
                      height: 20,
                      child: IgnorePointer(
                        child: Container(
                            transformAlignment: const Alignment(0, 0),
                            transform: Matrix4.rotationZ(e.hdg),
                            child: SvgPicture.asset("assets/images/chevron.svg",
                                colorFilter: const ColorFilter.mode(Colors.black87, BlendMode.srcIn))),
                      )))
                  .toList());
        });
  }
}

/// Wind speed / gust labels for weather stations in [bounds].
class WeatherObservationLabelsLayer extends StatelessWidget {
  final LatLngBounds bounds;

  const WeatherObservationLabelsLayer({super.key, required this.bounds});

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
        markers: getWeatherObservations(bounds)
            .map((e) => Marker(
                  height: 28,
                  width: 100,
                  point: e.latlng,
                  rotate: true,
                  alignment: Alignment.centerRight,
                  child: Container(
                    transform: Matrix4.translationValues(-14, 0, 0),
                    child: Row(
                      children: [
                        IgnorePointer(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(Radius.circular(10)),
                            child: Container(
                              color: e.color,
                              child:
                                  // space for arrow
                                  Padding(
                                padding: const EdgeInsets.only(left: 28, right: 8),
                                child: Text.rich(
                                  TextSpan(children: [
                                    TextSpan(text: printValue(UnitType.speed, e.windSpd!, digits: 2, decimals: 0)!),
                                    TextSpan(
                                        text: (e.windGust != null
                                            ? " g${printValue(UnitType.speed, e.windGust!, digits: 2, decimals: 0)}"
                                            : ''),
                                        style: const TextStyle(fontSize: 13))
                                  ]),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: const TextStyle(
                                      color: Colors.black, fontSize: 18, overflow: TextOverflow.visible),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList());
  }
}

/// Wind direction arrows for weather stations in [bounds].
class WeatherObservationArrowsLayer extends StatelessWidget {
  final LatLngBounds bounds;

  const WeatherObservationArrowsLayer({super.key, required this.bounds});

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
        markers: getWeatherObservations(bounds)
            .map(
              (e) => Marker(
                width: 14.0,
                height: 14.0,
                point: e.latlng,
                rotate: false,
                alignment: Alignment.center,
                child: IgnorePointer(
                  child: (e.windDir == null || (e.windSpd ?? 0) < 0.01)
                      ? Padding(
                          padding: const EdgeInsets.all(2),
                          child: Container(
                              decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          )),
                        )
                      : Container(
                          transformAlignment: const Alignment(0, 0),
                          transform: Matrix4.rotationZ((e.windDir ?? 0) * pi / 180 + pi),
                          child: SvgPicture.asset("assets/images/simple_arrow.svg",
                              colorFilter: const ColorFilter.mode(Colors.black87, BlendMode.srcIn))),
                ),
              ),
            )
            .toList());
  }
}

/// GA planes from ADSB-in.
class AdsbPlanesLayer extends StatelessWidget {
  final MapController mapController;

  const AdsbPlanesLayer({super.key, required this.mapController});

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
        markers: Provider.of<ADSB>(context)
            .planes
            .values
            .map(
              (e) => Marker(
                width: 50.0,
                height: 50.0,
                point: e.latlng,
                child: Container(
                  transformAlignment: const Alignment(0, 0),
                  transform: Matrix4.rotationZ(-mapController.camera.rotation * pi / 180),
                  child: Opacity(
                    opacity: getGAtransparency(e.alt - (myTelemetry.geo?.alt ?? 0)),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        /// --- GA icon
                        Container(
                          transformAlignment: const Alignment(0, 0),
                          transform: Matrix4.rotationZ((mapController.camera.rotation + e.hdg) * pi / 180),
                          child: e.getIcon(),
                        ),

                        Container(
                          transform: Matrix4.translationValues(50, 20, 0),
                          transformAlignment: const Alignment(0, 0),
                          child: Text(
                            e.id,
                            maxLines: 1,
                            style: const TextStyle(color: Colors.black, fontSize: 11, overflow: TextOverflow.visible),
                          ),
                        ),

                        /// --- Relative Altitude
                        if (myTelemetry.geo != null)
                          Container(
                              transform: Matrix4.translationValues(40, 0, 0),
                              transformAlignment: const Alignment(0, 0),
                              child: Text.rich(
                                TextSpan(children: [
                                  WidgetSpan(
                                    child: Icon(
                                      (e.alt - myTelemetry.geo!.alt) > 0
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      color: Colors.black,
                                      size: 21,
                                    ),
                                  ),
                                  richValue(UnitType.distFine, (e.alt - myTelemetry.geo!.alt).abs(),
                                      digits: 5,
                                      valueStyle: const TextStyle(color: Colors.black),
                                      unitStyle: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                                ]),
                                overflow: TextOverflow.visible,
                                softWrap: false,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 16),
                              )),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList());
  }
}

/// Live locations of the other pilots in the group.
class GroupPilotsLayer extends StatelessWidget {
  final MapController mapController;

  const GroupPilotsLayer({super.key, required this.mapController});

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: Provider.of<Group>(context)
          .activePilots
          .map((pilot) => Marker(
              point: pilot.geo!.latlng,
              width: 40,
              height: 40,
              child: Container(
                  transformAlignment: const Alignment(0, 0),
                  transform: Matrix4.rotationZ(-mapController.camera.rotation * pi / 180),
                  child: PilotMarker(
                    pilot,
                    20,
                    hdg: pilot.geo!.hdg + mapController.camera.rotation * pi / 180,
                    relAlt: pilot.geo!.alt - myTelemetry.geo!.alt,
                  ))))
          .toList(),
    );
  }
}

/// Flight traces of other pilots in the group.
class GroupPilotTracesLayer extends StatelessWidget {
  const GroupPilotTracesLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final pilots = Provider.of<Group>(context).activePilots;
    if (pilots.isEmpty) return Container();
    return PolylineLayer(polylines: pilots.map((e) => e.buildFlightTrace()).toList());
  }
}

/// Marks where along the selected waypoint path we are estimated to run out of fuel.
class FuelWarningLayer extends StatelessWidget {
  const FuelWarningLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: myTelemetry,
        builder: (context, _) {
          return Consumer<ActivePlan>(builder: (context, activePlan, _) {
            if (myTelemetry.fuelReportController.getSumFuelStat(myTelemetry.recordGeo) != null &&
                myTelemetry.geo != null &&
                activePlan.selectedWp != null) {
              final waypointETA = activePlan.getSelectedWp()!.eta(myTelemetry.geo!, 1);
              final enduranceDist = myTelemetry.speedSmooth.value *
                  myTelemetry.fuelReportController
                      .getSumFuelStat(myTelemetry.recordGeo)!
                      .extrapolateEndurance(myTelemetry.fuelReportController.fuelReports.last, from: clock.now())
                      .inSeconds;

              if (waypointETA.distance >= enduranceDist && enduranceDist >= 0) {
                final fuelIntercept = activePlan.getSelectedWp()!.interpolate(
                    enduranceDist, waypointETA.pathIntercept?.index ?? 0,
                    initialLatlng: myTelemetry.geo!.latlng);

                return MarkerLayer(
                  markers: [
                    Marker(
                      width: 50,
                      height: 50,
                      point: fuelIntercept.latlng,
                      child: const Stack(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Center(
                              child: Icon(
                                Icons.circle,
                                size: 30,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.warning_rounded,
                            size: 50,
                            color: Colors.black,
                          ),
                          Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 11, left: 3),
                              child: Icon(
                                Icons.local_gas_station,
                                size: 25,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                );
              } else {
                return Container();
              }
            } else {
              return Container();
            }
          });
        });
  }
}

/// "ME" live location marker.
class MyLocationLayer extends StatelessWidget {
  const MyLocationLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: myTelemetry,
        builder: (context, _) {
          if (myTelemetry.geo != null) {
            return MarkerLayer(
              markers: [
                Marker(
                  width: 50.0,
                  height: 50.0,
                  point: myTelemetry.geo!.latlng,
                  child: Container(
                    transformAlignment: const Alignment(0, 0),
                    transform: Matrix4.rotationZ(myTelemetry.geo!.hdg),
                    child: Image.asset("assets/images/red_arrow.png"),
                  ),
                ),
              ],
            );
          } else {
            return Container();
          }
        });
  }
}
