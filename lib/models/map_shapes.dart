import 'dart:ui';

import 'package:latlong2/latlong.dart';

import 'package:xcnav/models/map_camera.dart';

enum LinePattern { solid, dotted, dashed }

/// A line drawn on the map. Rendered natively by MapLibre (or painted on static previews).
class MapPolyline {
  final List<LatLng> points;
  final Color color;

  /// Logical pixels
  final double width;
  final LinePattern pattern;

  /// Outline drawn around the line ([borderWidth] on each side)
  final Color? borderColor;
  final double borderWidth;

  /// Returned by hit tests (eg. waypoint id)
  final String? hitValue;

  const MapPolyline({
    required this.points,
    required this.color,
    this.width = 3,
    this.pattern = LinePattern.solid,
    this.borderColor,
    this.borderWidth = 0,
    this.hitValue,
  });
}

/// A filled area drawn on the map.
class MapPolygon {
  final List<LatLng> points;
  final Color fillColor;
  final Color? borderColor;
  final double borderWidth;
  final LinePattern borderPattern;
  final String? hitValue;

  const MapPolygon({
    required this.points,
    required this.fillColor,
    this.borderColor,
    this.borderWidth = 0,
    this.borderPattern = LinePattern.solid,
    this.hitValue,
  });
}

/// Approximate circle ([radius] meters) as a closed ring of points.
List<LatLng> circlePoints(LatLng center, double radius, {int segments = 72}) {
  const calc = Distance(roundResult: false);
  return List.generate(segments, (i) => calc.offset(center, radius, 360 * i / segments));
}

/// CSS color string MapLibre understands
String cssColor(Color color) {
  int c(double v) => (v * 255).round().clamp(0, 255);
  return "rgba(${c(color.r)},${c(color.g)},${c(color.b)},${color.a.toStringAsFixed(3)})";
}

/// A group of shapes that update together. Each group becomes one GeoJSON source on the map,
/// so put fast changing shapes (eg. the line to the next waypoint) in their own group.
///
/// Groups are drawn in list order. Within a group: fills, then line borders, then lines.
class ShapeLayer {
  /// Stable id. Must be unique within a map.
  final String id;
  final List<MapPolygon> polygons;
  final List<MapPolyline> lines;

  const ShapeLayer(this.id, {this.polygons = const [], this.lines = const []});

  bool get isEmpty => polygons.isEmpty && lines.isEmpty;

  static List<double> _coord(LatLng p) => [p.longitude, p.latitude];

  /// GeoJSON FeatureCollection. Styling is carried in the feature properties, see [shapeStyleLayers].
  Map<String, dynamic> toGeoJson() {
    final features = <Map<String, dynamic>>[];
    for (final p in polygons) {
      if (p.points.length < 3) continue;
      final ring = [...p.points.map(_coord), _coord(p.points.first)];
      features.add({
        "type": "Feature",
        "properties": {"kind": "fill", "color": cssColor(p.fillColor), if (p.hitValue != null) "hit": p.hitValue},
        "geometry": {
          "type": "Polygon",
          "coordinates": [ring]
        },
      });
      if (p.borderColor != null && p.borderWidth > 0) {
        features.add({
          "type": "Feature",
          "properties": {
            "kind": "line",
            "color": cssColor(p.borderColor!),
            "width": p.borderWidth,
            "pattern": p.borderPattern.name,
            "border": 0.0,
          },
          "geometry": {"type": "LineString", "coordinates": ring},
        });
      }
    }
    for (final l in lines) {
      if (l.points.length < 2) continue;
      features.add({
        "type": "Feature",
        "properties": {
          "kind": "line",
          "color": cssColor(l.color),
          "width": l.width,
          "pattern": l.pattern.name,
          "border": l.borderColor != null ? l.borderWidth : 0.0,
          if (l.borderColor != null) "borderColor": cssColor(l.borderColor!),
          if (l.hitValue != null) "hit": l.hitValue,
        },
        "geometry": {"type": "LineString", "coordinates": l.points.map(_coord).toList()},
      });
    }
    return {"type": "FeatureCollection", "features": features};
  }

  /// Hit values of the lines within [tolerance] logical pixels of [screenPoint], top-most first.
  List<String> hitTestLines(MapCamera camera, Offset screenPoint, {double tolerance = 15}) {
    final List<String> hits = [];
    for (final line in lines.reversed) {
      if (line.hitValue == null || line.points.length < 2) continue;
      final pts = line.points.map(camera.latLngToScreen).toList();
      for (int i = 0; i + 1 < pts.length; i++) {
        final a = pts[i];
        final b = pts[i + 1];
        if (a == null || b == null) continue;
        if (distanceToSegment(screenPoint, a, b) <= tolerance + line.width / 2) {
          hits.add(line.hitValue!);
          break;
        }
      }
    }
    return hits;
  }
}

/// Distance from [p] to the segment [a]-[b]
double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lenSq == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Native style layer suffixes for a [ShapeLayer], bottom to top.
const shapeStyleLayers = ["fill", "casing", "solid", "dotted", "dashed"];

/// MapLibre `line-dasharray` (in line widths) for each pattern
const Map<LinePattern, List<double>> lineDashArrays = {
  LinePattern.dotted: [0, 2],
  LinePattern.dashed: [3, 2],
};
