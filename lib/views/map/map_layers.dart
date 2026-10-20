import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/dialogs/pilot_info.dart';
import 'package:xcnav/models/airport_info.dart';
import 'package:xcnav/models/airspace.dart';
import 'package:xcnav/models/ga.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/map_shapes.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/models/tfr.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/views/map/map_markers.dart';
import 'package:xcnav/views/map/map_symbols.dart';
import 'package:xcnav/weather_observation_service.dart';
import 'package:xcnav/widgets/pilot_marker.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

// ============================================================================
//
//  Shapes (drawn natively by the map)
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

/// Flight traces of other pilots in the group.
ShapeLayer groupTraceShapes(Iterable<Pilot> pilots) =>
    ShapeLayer("groupTraces", lines: pilots.map((e) => e.buildFlightTrace()).toList());

// ============================================================================
//
//  Markers (drawn by the map, see MapSymbol)
//
// ----------------------------------------------------------------------------

/// Airports show from this zoom level. Further out there are too many.
const double airportsMinZoom = 7;

/// Airport codes show from this zoom level
const double airportLabelsMinZoom = 9;

/// OpenAIP airports as tappable icons, with their code when zoomed in.
List<SymbolLayer> airportSymbols(List<AirportInfo> airports, void Function(AirportInfo airport) onTap) => [
      SymbolLayer("airports",
          minZoom: airportsMinZoom,
          symbols: airports
              .map((e) => MapSymbol(
                    id: e.id,
                    point: e.latlng,
                    width: 26,
                    height: 26,
                    imageKey: "airport_${e.hasTower}",
                    onTap: () => onTap(e),
                    // Sectional style: blue towered, magenta non-towered
                    child: Container(
                      decoration: BoxDecoration(
                          color: e.hasTower ? Colors.blue.shade800 : Colors.pink.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2)),
                      child: Transform.rotate(
                          angle: pi / 4, child: const Icon(Icons.local_airport, size: 16, color: Colors.white)),
                    ),
                  ))
              .toList()),
      SymbolLayer("airportLabels",
          minZoom: airportLabelsMinZoom,
          symbols: airports
              .where((e) => e.code != null)
              .map((e) => MapSymbol(
                    id: e.id,
                    point: e.latlng,
                    width: 60,
                    height: 13 + 16,
                    // Under the icon
                    alignment: Alignment.bottomCenter,
                    imageKey: "airportLabel_${e.code}",
                    child: Padding(
                      padding: const EdgeInsets.only(top: 13),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          color: Colors.white70,
                          child: Text(e.code!,
                              maxLines: 1, style: const TextStyle(color: Colors.black, fontSize: 11, height: 1.4)),
                        ),
                      ),
                    ),
                  ))
              .toList()),
    ];

/// A single point waypoint as a pin, [height] tall
MapSymbol waypointSymbol(Waypoint waypoint,
        {double height = 60 * 0.8, VoidCallback? onTap, VoidCallback? onLongPress}) =>
    MapSymbol(
      id: waypoint.id,
      point: waypoint.latlng.first,
      width: height * 2 / 3,
      height: height,
      alignment: Alignment.topCenter,
      imageKey: "waypoint_${waypoint.color}_${waypoint.icon}_$height",
      onTap: onTap,
      onLongPress: onLongPress,
      child: WaypointMarker(waypoint, height),
    );

/// Chevrons along the path to the selected waypoint.
SymbolLayer nextWaypointBarbSymbols(ActivePlan plan, Geo geo) => SymbolLayer("nextWaypointBarbs",
    rotateWithMap: true,
    symbols: plan
        .buildNextWpBarbs(geo, (settingsMgr.displayUnitDist.value == DisplayUnitsDist.metric ? 1000 : 1609.344))
        .mapIndexed((index, e) => MapSymbol(
              id: "$index",
              point: e.latlng,
              width: 20,
              height: 20,
              imageKey: "nextWaypointBarb",
              rotation: e.hdg * 180 / pi,
              child: SvgPicture.asset("assets/images/chevron.svg",
                  colorFilter: const ColorFilter.mode(Colors.black87, BlendMode.srcIn)),
            ))
        .toList());

/// Weather stations show from this zoom level
const double weatherMinZoom = 6;

/// Wind speed / gust labels and direction arrows for weather stations.
List<SymbolLayer> weatherSymbols(Iterable<WeatherObservation> observations) {
  final stations = observations.toList();
  return [
    // Labels, to the right of the arrows
    SymbolLayer("weatherLabels",
        minZoom: weatherMinZoom,
        symbols: stations.where((e) => e.windSpd != null).map((e) {
          final speed = printValue(UnitType.speed, e.windSpd!, digits: 2, decimals: 0)!;
          final gust = e.windGust != null ? " g${printValue(UnitType.speed, e.windGust!, digits: 2, decimals: 0)}" : "";
          return MapSymbol(
            id: e.stationId,
            point: e.latlng,
            width: 100,
            height: 28,
            alignment: Alignment.centerRight,
            // The label starts a little left of the point, around the arrow
            overflow: const EdgeInsets.only(left: 14),
            imageKey: "weatherLabel_${speed}_${gust}_${e.color.toARGB32()}",
            child: Container(
              transform: Matrix4.translationValues(-14, 0, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    child: Container(
                      color: e.color,
                      child:
                          // space for arrow
                          Padding(
                        padding: const EdgeInsets.only(left: 28, right: 8),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: speed),
                            TextSpan(text: gust, style: const TextStyle(fontSize: 13)),
                          ]),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(color: Colors.black, fontSize: 18, overflow: TextOverflow.visible),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList()),
    // Arrows (a dot when calm)
    SymbolLayer("weatherArrows",
        minZoom: weatherMinZoom,
        rotateWithMap: true,
        symbols: stations.map((e) {
          final calm = e.windDir == null || (e.windSpd ?? 0) < 0.01;
          return MapSymbol(
            id: e.stationId,
            point: e.latlng,
            width: 14,
            height: 14,
            imageKey: calm ? "weatherCalm" : "weatherArrow",
            rotation: calm ? 0 : e.windDir! + 180,
            child: calm
                ? Padding(
                    padding: const EdgeInsets.all(2),
                    child: Container(decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle)),
                  )
                : SvgPicture.asset("assets/images/simple_arrow.svg",
                    colorFilter: const ColorFilter.mode(Colors.black87, BlendMode.srcIn)),
          );
        }).toList()),
  ];
}

/// GA planes from ADSB-in: icons turned to their heading, with upright labels. Fainter the further above / below me.
List<SymbolLayer> adsbSymbols(Iterable<GA> planes, Geo? myGeo) {
  final list = planes.toList();
  double opacity(GA e) => getGAtransparency(e.alt - (myGeo?.alt ?? 0));
  return [
    SymbolLayer("adsbPlanes",
        rotateWithMap: true,
        symbols: list
            .map((e) => MapSymbol(
                  id: e.id,
                  point: e.latlng,
                  width: 50,
                  height: 50,
                  imageKey: "adsbPlane_${e.type.name}_${e.warning}",
                  rotation: e.hdg,
                  opacity: opacity(e),
                  child: e.getIcon(),
                ))
            .toList()),
    SymbolLayer("adsbLabels",
        symbols: list.map((e) {
          final relAlt = myGeo == null ? null : e.alt - myGeo.alt;
          final relAltSpan = relAlt == null
              ? null
              : richValue(UnitType.distFine, relAlt.abs(),
                  digits: 5,
                  valueStyle: const TextStyle(color: Colors.black),
                  unitStyle: TextStyle(color: Colors.grey.shade700, fontSize: 12));
          return MapSymbol(
            id: e.id,
            point: e.latlng,
            width: 50,
            height: 50,
            overflow: const EdgeInsets.only(right: 160, bottom: 40),
            imageKey: "adsbLabel_${e.id}_${relAlt == null ? "" : "${relAlt > 0 ? "+" : "-"}${relAltSpan!.toPlainText()}"}",
            opacity: opacity(e),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
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
                if (relAlt != null)
                  Container(
                      transform: Matrix4.translationValues(40, 0, 0),
                      transformAlignment: const Alignment(0, 0),
                      child: Text.rich(
                        TextSpan(children: [
                          WidgetSpan(
                            child: Icon(
                              relAlt > 0 ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              color: Colors.black,
                              size: 21,
                            ),
                          ),
                          relAltSpan!,
                        ]),
                        overflow: TextOverflow.visible,
                        softWrap: false,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 16),
                      )),
              ],
            ),
          );
        }).toList()),
  ];
}

/// Live locations of the other pilots in the group: heading arrows, and avatars with labels. Tap for pilot info.
List<SymbolLayer> groupPilotSymbols(BuildContext context, Iterable<Pilot> pilots, Geo? myGeo) {
  final list = pilots.where((e) => e.geo != null).toList();
  return [
    SymbolLayer("pilotArrows",
        rotateWithMap: true,
        symbols: list
            .map((pilot) => MapSymbol(
                  id: pilot.id,
                  point: pilot.geo!.latlng,
                  width: 40,
                  height: 40,
                  imageKey: "pilotArrow",
                  rotation: pilot.geo!.hdg * 180 / pi,
                  // Points out from the edge of the avatar
                  child: Transform.translate(
                      offset: const Offset(0, -12),
                      child: SvgPicture.asset("assets/images/pilot_direction_arrow.svg", clipBehavior: Clip.none)),
                ))
            .toList()),
    SymbolLayer("pilots",
        symbols: list.map((pilot) {
          final relAlt = pilot.geo!.alt - (myGeo?.alt ?? pilot.geo!.alt);
          final showName = pilot.avatar == null || settingsMgr.showPilotNames.value;
          final relAltText = "${relAlt > 0 ? "+" : "-"}${richValue(UnitType.distFine, relAlt.abs(), digits: 5).toPlainText()}";
          return MapSymbol(
            id: pilot.id,
            point: pilot.geo!.latlng,
            width: 40,
            height: 40,
            overflow: const EdgeInsets.only(right: 260, bottom: 50),
            imageKey: "pilot_${pilot.id}_${pilot.avatar.hashCode}_${showName ? pilot.name : ""}_$relAltText",
            precache: [if (pilot.avatar != null) pilot.avatar!.image],
            onTap: () => showPilotInfo(context, pilot.id),
            child: PilotMarker(pilot, 20, relAlt: relAlt),
          );
        }).toList()),
  ];
}

/// Marks where along the selected waypoint path we are estimated to run out of fuel.
SymbolLayer fuelWarningSymbols(ActivePlan activePlan) {
  LatLng? point;
  final fuelStat = myTelemetry.fuelReportController.getSumFuelStat(myTelemetry.recordGeo);
  if (fuelStat != null && myTelemetry.geo != null && activePlan.selectedWp != null) {
    final waypointETA = activePlan.getSelectedWp()!.eta(myTelemetry.geo!, 1);
    final enduranceDist = myTelemetry.speedSmooth.value *
        fuelStat.extrapolateEndurance(myTelemetry.fuelReportController.fuelReports.last, from: clock.now()).inSeconds;
    if (waypointETA.distance >= enduranceDist && enduranceDist >= 0) {
      point = activePlan
          .getSelectedWp()!
          .interpolate(enduranceDist, waypointETA.pathIntercept?.index ?? 0, initialLatlng: myTelemetry.geo!.latlng)
          .latlng;
    }
  }
  return SymbolLayer("fuelWarning", symbols: [
    if (point != null)
      MapSymbol(id: "fuel", point: point, width: 50, height: 50, imageKey: "fuelWarning", child: const FuelWarningIcon()),
  ]);
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

/// "ME": where I am, pointing where I'm headed
SymbolLayer myLocationSymbols(Geo? geo, {String id = "myLocation", double size = 50}) =>
    SymbolLayer(id, rotateWithMap: true, symbols: [
      if (geo != null)
        MapSymbol(
          id: "me",
          point: geo.latlng,
          width: size,
          height: size,
          imageKey: "myLocation_$size",
          rotation: geo.hdg * 180 / pi,
          child: Image.asset("assets/images/red_arrow.png"),
        ),
    ]);

/// "ME" live location marker, as a Flutter widget (for `StaticMap`, which has no map engine to draw symbols)
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
