import 'dart:math';
import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:xcnav/models/airspace.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

/// Elevation Sample for a given LatLng coordinate
class ElevSample {
  final LatLng latlng;
  final double elev;
  final double dist;

  ElevSample(this.latlng, this.dist, this.elev);
}

/// Show airspace floors this far (meters) above the top of the plot
const _airspaceFloorLookUp = 600.0;

/// Head room above a stretched-to airspace floor
const _airspaceFloorMargin = 150.0;

/// Side profile of the pilot's recent altitude, the ground below, and the ground ahead.
///
/// X axis is time (ms since epoch). Samples ahead of the pilot are placed at `last.time + dist * distScale`.
class ElevationPlot extends StatelessWidget {
  final double liveVario;
  final double liveSpeed;
  final List<Geo> geoData;
  final List<ElevSample> groundData;

  final double distScale;

  final Waypoint? waypoint;
  final ETA? waypointETA;

  final bool showPilotIcon;

  /// Airspaces to draw a cross section of, along the track and the look-ahead.
  final List<Airspace> airspaces;

  const ElevationPlot(this.geoData, this.groundData, this.distScale,
      {super.key,
      this.waypoint,
      this.waypointETA,
      this.showPilotIcon = true,
      this.airspaces = const [],
      required this.liveVario,
      required this.liveSpeed});

  @override
  Widget build(BuildContext context) {
    if (geoData.isEmpty) return Container();

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;

      final futureGround = groundData.map((e) => e.elev).toList();

      // --- Airspace cross section (past track, then look-ahead)
      final airspaceSections = airspaces.isEmpty
          ? <AirspaceSection>[]
          : airspaceCrossSection([
              ...geoData
                  .where((e) => e.ground != null)
                  .map((e) => AirspaceProbe(e.time.toDouble(), e.latlng, e.ground!)),
              ...groundData.map((e) => AirspaceProbe(geoData.last.time + e.dist, e.latlng, e.elev)),
            ], airspaces);

      // --- Common misc.
      double maxElevUnsnapped = max(geoData.map((e) => e.alt).max, futureGround.maxOrNull ?? 0);
      // Stretch up to show airspace floors that are close above us
      for (final section in airspaceSections) {
        final floor = section.points.map((e) => e.bottom).min;
        if (floor > maxElevUnsnapped && floor < maxElevUnsnapped + _airspaceFloorLookUp) {
          maxElevUnsnapped = floor + _airspaceFloorMargin;
        }
      }

      // --- Set vertical grid resolution
      final double vertGridResScale = max(1, ((maxElevUnsnapped / height) / 5).floor() * 2).toDouble();
      final double vertGridRes =
          (settingsMgr.displayUnitDist.value == DisplayUnitsDist.metric ? 100 : 152.4) * vertGridResScale;

      final double maxElev = ((maxElevUnsnapped + vertGridRes / 2) / vertGridRes).ceil() * vertGridRes;

      final historyGround = geoData.map((e) => e.ground).nonNulls;
      final double minElev =
          ((min(historyGround.minOrNull ?? 0, futureGround.minOrNull ?? 0) - vertGridRes / 2) / vertGridRes).floor() *
              vertGridRes;

      // --- Horizontal range
      final first = geoData.first;
      final last = geoData.last;
      final double farthestDist = groundData.lastOrNull?.dist ?? 0;
      final double rangeX = max(1, last.time - first.time + farthestDist);

      double pxPerX = width / rangeX;
      double minX = first.time.toDouble();
      if (showPilotIcon) {
        // limit stretch to keep things in view of the center
        final rightPad = futureGround.isEmpty ? 80 : 0;
        final leftOffset = width * (last.time - first.time) / rangeX;
        final correction = max(0, 30 - leftOffset);
        pxPerX = (width - rightPad - correction) / rangeX;
        minX -= correction / pxPerX;
      }
      final double maxX = minX + width / pxPerX;
      final double pxPerY = height / (maxElev - minElev);

      Offset toPixel(double x, double y) => Offset((x - minX) * pxPerX, height - (y - minElev) * pxPerY);

      // --- Vario Trendline
      final pilot = toPixel(last.time.toDouble(), last.alt);
      final double trendDx = liveSpeed * distScale;
      final trendAngle = atan2(-liveVario * pxPerY, trendDx * pxPerX);

      // --- Waypoint
      final wp = waypoint;
      final eta = waypointETA;
      List<FlSpot> pathSpots = [];
      Offset? wpPixel;

      /// Fallback for when the waypoint's own elevation isn't loaded yet: nearest look-ahead ground sample.
      double groundAt(double scaledDist) =>
          minBy(groundData, (ElevSample e) => (e.dist - scaledDist).abs())?.elev ?? historyGround.lastOrNull ?? 0;

      if (wp != null && eta != null) {
        if (wp.isPath) {
          // groundData is sampled along the path (after the intercept), so trace the ground from the intercept to the
          // end of the path rather than just connecting the path vertices.
          final pathStart = (eta.pathIntercept?.dist ?? 0) * distScale;
          final pathEnd = eta.distance * distScale;
          pathSpots = [
            FlSpot(last.time + pathStart, groundAt(pathStart)),
            ...groundData
                .where((e) => e.dist > pathStart && e.dist < pathEnd)
                .map((e) => FlSpot(last.time + e.dist, e.elev)),
            if (pathEnd <= farthestDist) FlSpot(last.time + pathEnd, groundAt(pathEnd)),
          ];
        } else {
          final wpEta = eta.distance * distScale;
          wpPixel = toPixel(last.time + wpEta, wp.elevation[0] ?? groundAt(wpEta));
        }
      }

      final glideSlope = myTelemetry.glideSlope;
      final arrowSize = width / 10;

      return Stack(clipBehavior: Clip.hardEdge, children: [
        // --- Airspace (behind ground)
        if (airspaceSections.isNotEmpty)
          Positioned.fill(child: CustomPaint(painter: _AirspacePainter(airspaceSections, toPixel))),

        LineChart(
            duration: Duration.zero,
            LineChartData(
                minX: minX,
                maxX: maxX,
                minY: minElev,
                maxY: maxElev,
                baselineX: last.time.toDouble(),
                clipData: const FlClipData.all(),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                gridData: FlGridData(
                    horizontalInterval: vertGridRes,
                    verticalInterval: const Duration(minutes: 5).inMilliseconds.toDouble(),
                    getDrawingHorizontalLine: (_) => const FlLine(color: Colors.white24, strokeWidth: 1),
                    // Only draw short ticks along the top and bottom edges
                    getDrawingVerticalLine: (_) => FlLine(
                        color: Colors.white24,
                        strokeWidth: 1,
                        dashArray: height > 40 ? [20, (height - 40).toInt()] : null)),
                titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                        sideTitleAlignment: SideTitleAlignment.inside,
                        drawBelowEverything: false,
                        sideTitles: SideTitles(
                            showTitles: true,
                            interval: vertGridRes,
                            reservedSize: 80,
                            minIncluded: false,
                            getTitlesWidget: (value, meta) => Transform.translate(
                                offset: const Offset(4, 10),
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(printValue(UnitType.distFine, value, decimals: 0) ?? "",
                                        style: const TextStyle(color: Colors.white)))))),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
                lineBarsData: [
                  // --- Past Ground Level
                  LineChartBarData(
                      barWidth: 0,
                      dotData: const FlDotData(show: false),
                      spots: geoData
                          .where((e) => e.ground != null)
                          .map((e) => FlSpot(e.time.toDouble(), e.ground!.toDouble()))
                          .toList(),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.orange.shade600,
                      )),

                  // --- Future Ground Level
                  LineChartBarData(
                      barWidth: 0,
                      dotData: const FlDotData(show: false),
                      spots: groundData.map((e) => FlSpot(e.dist + last.time, e.elev)).toList(),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.orange.shade600,
                      )),

                  // --- Pilot Elevation Track
                  LineChartBarData(
                      color: Colors.blue,
                      barWidth: 5,
                      isStrokeCapRound: true,
                      isStrokeJoinRound: true,
                      dotData: const FlDotData(show: false),
                      spots: geoData.map((e) => FlSpot(e.time.toDouble(), e.alt)).toList()),

                  // --- Vario Trendline
                  if (trendDx > 0)
                    LineChartBarData(
                        color: Colors.white,
                        barWidth: 2,
                        dashArray: [10, 10],
                        dotData: const FlDotData(show: false),
                        spots: [
                          FlSpot(last.time.toDouble(), last.alt),
                          FlSpot(maxX, last.alt + liveVario * (maxX - last.time) / trendDx),
                        ]),

                  // --- Waypoint: Path
                  if (pathSpots.isNotEmpty)
                    LineChartBarData(
                        color: wp!.getColor(),
                        barWidth: 8,
                        isStrokeCapRound: true,
                        isStrokeJoinRound: true,
                        dotData: const FlDotData(show: false),
                        spots: pathSpots),
                ])),

        // --- Waypoint: Point
        if (wpPixel != null)
          Positioned(
              left: wpPixel.dx - 21,
              top: wpPixel.dy - 64,
              child: SizedBox(width: 42, height: 64, child: WaypointMarker(wp!, 64))),

        // --- Pilot Icon
        if (showPilotIcon)
          Positioned(
              left: pilot.dx - arrowSize / 2,
              top: pilot.dy - arrowSize / 2,
              child: Transform.rotate(
                  angle: trendAngle + pi / 2,
                  child: Image.asset("assets/images/red_arrow.png",
                      width: arrowSize, height: arrowSize, fit: BoxFit.fill))),

        // --- Vario
        if (showPilotIcon)
          Positioned(
              left: pilot.dx - 20,
              top: pilot.dy + 20,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 60),
                child: Text.rich(
                    TextSpan(children: [
                      richValue(UnitType.vario, liveVario,
                          valueStyle: const TextStyle(fontSize: 30),
                          unitStyle: const TextStyle(fontSize: 14, color: Colors.grey)),
                      if (glideSlope != null) TextSpan(text: "    ${glideSlope.round()}:1")
                    ]),
                    textAlign: TextAlign.right),
              )),
      ]);
    });
  }
}

/// Filled vertical slices of airspace, with the name along the floor.
class _AirspacePainter extends CustomPainter {
  final List<AirspaceSection> sections;
  final Offset Function(double x, double y) toPixel;

  _AirspacePainter(this.sections, this.toPixel);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final section in sections) {
      final color = section.airspace.color;
      final top = section.points.map((e) => toPixel(e.x, e.top)).toList();
      final bottom = section.points.map((e) => toPixel(e.x, e.bottom)).toList();

      final path = Path()..moveTo(top.first.dx, top.first.dy);
      for (final p in top.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      // A single sample still gets a sliver so it's visible
      if (top.length == 1) path.lineTo(top.first.dx + 2, top.first.dy);
      if (bottom.length == 1) path.lineTo(bottom.first.dx + 2, bottom.first.dy);
      for (final p in bottom.reversed) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();

      canvas.drawPath(path, Paint()..color = color.withAlpha(70));
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);

      // --- Label just above the floor, centered on the visible part
      final left = max(0.0, bottom.first.dx);
      final right = min(size.width, bottom.last.dx);
      if (right - left < 40) continue;
      final floorY = bottom.map((e) => e.dy).reduce(min).clamp(20.0, size.height);
      final label = TextPainter(
          text: TextSpan(
              text: section.airspace.name.isNotEmpty ? section.airspace.name : section.airspace.label,
              style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 3)])),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: "…")
        ..layout(maxWidth: right - left);
      label.paint(canvas, Offset((left + right - label.width) / 2, floorY - label.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _AirspacePainter oldDelegate) => true;
}
