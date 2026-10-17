import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/models/airport_info.dart';
import 'package:xcnav/models/airspace.dart';
import 'package:xcnav/models/ga.dart';
import 'package:xcnav/models/map_shapes.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/models/tfr.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/services/openaip_service.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/views/map/map_markers.dart';
import 'package:xcnav/views/map/xc_map.dart';
import 'package:xcnav/weather_observation_service.dart';
import 'package:xcnav/widgets/pilot_marker.dart';

// ============================================================================
//
//  Shapes (drawn natively by MapLibre)
//
// ----------------------------------------------------------------------------

/// TFR areas. Red when active within 3 hours.
ShapeLayer tfrShapes(List<TFR> tfrs) {
  final List<MapPolygon> polygons = [];
  for (final eachTfr in tfrs) {
    final color = eachTfr.isActive(const Duration(hours: 3)) ? Colors.red : Colors.orange;
    for (final shape in eachTfr.shapes) {
      polygons.add(MapPolygon(points: shape, fillColor: color.withAlpha(50), borderColor: color, borderWidth: 4));
    }
  }
  return ShapeLayer("tfr", polygons: polygons);
}

List<Airspace>? _airspaceCachedFor;
ShapeLayer _airspaceCachedLayer = const ShapeLayer("airspace");

/// OpenAIP airspace outlines (dashed for class D / E, like on sectionals)
ShapeLayer airspaceShapes(List<Airspace> airspaces) {
  // Same list, same layer instance: lets the map skip re-sending it
  if (!identical(airspaces, _airspaceCachedFor)) {
    _airspaceCachedFor = airspaces;
    _airspaceCachedLayer = ShapeLayer("airspace",
        polygons: airspaces
            .map((e) => MapPolygon(
                points: e.points,
                fillColor: e.color.withAlpha(25),
                borderColor: e.color.withAlpha(200),
                borderWidth: 2.5,
                borderPattern: e.dashed ? LinePattern.dashed : LinePattern.solid))
            .toList());
  }
  return _airspaceCachedLayer;
}

/// Circle around me showing the ADSB proximity warning radius.
ShapeLayer adsbProximityShape(LatLng center) {
  final ring = circlePoints(center, proximityProfileOptions[settingsMgr.adsbProximitySize.value]!.horizontalDist);
  return ShapeLayer("adsbProximity", lines: [MapPolyline(points: ring..add(ring.first), color: Colors.black54, width: 1)]);
}

/// Flight traces of other pilots in the group.
ShapeLayer groupTraceShapes(Iterable<Pilot> pilots) =>
    ShapeLayer("groupTraces", lines: pilots.map((e) => e.buildFlightTrace()).toList());

// ============================================================================
//
//  Markers (Flutter widgets over the map)
//
// ----------------------------------------------------------------------------

/// OpenAIP airports near [center] as tappable icons. Hidden when zoomed out.
class AirportsLayer extends StatelessWidget {
  final LatLng center;
  final void Function(AirportInfo airport) onTap;

  /// Hide below this zoom level, there are too many
  static const minZoom = 7;

  /// Show the airport code from this zoom level
  static const labelZoom = 9;

  const AirportsLayer({super.key, required this.center, required this.onTap});

  @override
  Widget build(BuildContext context) {
    openAipService.refresh(center);
    return ValueListenableBuilder<int>(
        valueListenable: XcMapScope.of(context).zoomLevel,
        builder: (context, zoom, _) {
          if (zoom < minZoom) return const SizedBox();
          final showLabel = zoom >= labelZoom;
          return ListenableBuilder(
              listenable: openAipService,
              builder: (context, _) => MarkerLayer(
                  markers: openAipService.airports
                      .map((e) => MapMarker(
                          key: ValueKey("airport_${e.id}"),
                          point: e.latlng,
                          width: 60,
                          // label space mirrored above, so the icon stays centered on the point
                          height: 26 + 2 * 16,
                          child: Column(
                            children: [
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: () => onTap(e),
                                // Sectional style: blue towered, magenta non-towered
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                      color: e.hasTower ? Colors.blue.shade800 : Colors.pink.shade700,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2)),
                                  child: Transform.rotate(
                                      angle: pi / 4,
                                      child: const Icon(Icons.local_airport, size: 16, color: Colors.white)),
                                ),
                              ),
                              if (showLabel && e.code != null)
                                IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 3),
                                    color: Colors.white70,
                                    child: Text(e.code!,
                                        maxLines: 1,
                                        style: const TextStyle(color: Colors.black, fontSize: 11, height: 1.4)),
                                  ),
                                ),
                            ],
                          )))
                      .toList()));
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
                  .map((e) => MapMarker(
                      point: e.latlng,
                      width: 20,
                      height: 20,
                      rotateWithMap: true,
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

/// Wind speed / gust labels and direction arrows for weather stations in view.
class WeatherObservationsLayer extends StatelessWidget {
  /// Hide below this zoom level
  static const minZoom = 6;

  const WeatherObservationsLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = XcMapScope.of(context);
    return ValueListenableBuilder<int>(
        valueListenable: controller.zoomLevel,
        builder: (context, zoom, _) {
          final camera = controller.camera.value;
          if (camera == null || zoom < minZoom) return const SizedBox();
          final observations = getWeatherObservations(camera.visibleBounds).toList();
          return Stack(fit: StackFit.expand, children: [
            // Labels
            MarkerLayer(
                markers: observations
                    .map((e) => MapMarker(
                          height: 28,
                          width: 100,
                          point: e.latlng,
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
                                            TextSpan(
                                                text: printValue(UnitType.speed, e.windSpd!, digits: 2, decimals: 0)!),
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
                    .toList()),
            // Arrows
            MarkerLayer(
                markers: observations
                    .map(
                      (e) => MapMarker(
                        width: 14.0,
                        height: 14.0,
                        point: e.latlng,
                        rotateWithMap: true,
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
                    .toList()),
          ]);
        });
  }
}

/// GA planes from ADSB-in.
class AdsbPlanesLayer extends StatelessWidget {
  const AdsbPlanesLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final planes = Provider.of<ADSB>(context).planes.values.toList();
    return Stack(fit: StackFit.expand, children: [
      // --- GA icon (in the map's frame)
      MarkerLayer(
          markers: planes
              .map((e) => MapMarker(
                    width: 50.0,
                    height: 50.0,
                    point: e.latlng,
                    rotateWithMap: true,
                    child: Opacity(
                      opacity: getGAtransparency(e.alt - (myTelemetry.geo?.alt ?? 0)),
                      child: Container(
                        transformAlignment: const Alignment(0, 0),
                        transform: Matrix4.rotationZ(e.hdg * pi / 180),
                        child: e.getIcon(),
                      ),
                    ),
                  ))
              .toList()),
      // --- Labels (upright)
      MarkerLayer(
          markers: planes
              .map((e) => MapMarker(
                    width: 50.0,
                    height: 50.0,
                    point: e.latlng,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: getGAtransparency(e.alt - (myTelemetry.geo?.alt ?? 0)),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              transform: Matrix4.translationValues(50, 20, 0),
                              transformAlignment: const Alignment(0, 0),
                              child: Text(
                                e.id,
                                maxLines: 1,
                                style:
                                    const TextStyle(color: Colors.black, fontSize: 11, overflow: TextOverflow.visible),
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
                  ))
              .toList()),
    ]);
  }
}

/// Live locations of the other pilots in the group.
class GroupPilotsLayer extends StatelessWidget {
  const GroupPilotsLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final pilots = Provider.of<Group>(context).activePilots;
    if (pilots.isEmpty) return const SizedBox();
    // Heading arrows are drawn relative to the screen
    return ValueListenableBuilder<double>(
        valueListenable: XcMapScope.of(context).bearing,
        builder: (context, bearing, _) => MarkerLayer(
              markers: pilots
                  .map((pilot) => MapMarker(
                      point: pilot.geo!.latlng,
                      width: 40,
                      height: 40,
                      child: PilotMarker(
                        pilot,
                        20,
                        hdg: pilot.geo!.hdg - bearing * pi / 180,
                        relAlt: pilot.geo!.alt - (myTelemetry.geo?.alt ?? pilot.geo!.alt),
                      )))
                  .toList(),
            ));
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
                    MapMarker(
                      width: 50,
                      height: 50,
                      point: fuelIntercept.latlng,
                      child: const FuelWarningIcon(),
                    )
                  ],
                );
              } else {
                return const SizedBox();
              }
            } else {
              return const SizedBox();
            }
          });
        });
  }
}

/// Fuel can with a warning triangle
class FuelWarningIcon extends StatelessWidget {
  final double size;

  const FuelWarningIcon({super.key, this.size = 50});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(top: size / 5),
          child: Center(
            child: Icon(
              Icons.circle,
              size: size * 0.6,
              color: Colors.black,
            ),
          ),
        ),
        Icon(
          Icons.warning_rounded,
          size: size,
          color: Colors.black,
        ),
        Center(
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.22, left: size * 0.06),
            child: Icon(
              Icons.local_gas_station,
              size: size / 2,
              color: Colors.red,
            ),
          ),
        ),
      ],
    );
  }
}

/// "ME" live location marker.
class MyLocationLayer extends StatelessWidget {
  final double size;

  const MyLocationLayer({super.key, this.size = 50});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: myTelemetry,
        builder: (context, _) {
          if (myTelemetry.geo != null) {
            return MarkerLayer(
              markers: [
                MapMarker(
                  width: size,
                  height: size,
                  point: myTelemetry.geo!.latlng,
                  rotateWithMap: true,
                  child: IgnorePointer(
                    child: Container(
                      transformAlignment: const Alignment(0, 0),
                      transform: Matrix4.rotationZ(myTelemetry.geo!.hdg),
                      child: Image.asset("assets/images/red_arrow.png"),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return const SizedBox();
          }
        });
  }
}
