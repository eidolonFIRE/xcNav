import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:latlong2/latlong.dart';

/// Geographic bounding box. Corners can be given in any order.
class LatLngBounds {
  double north;
  double south;
  double east;
  double west;

  LatLngBounds(LatLng corner1, LatLng corner2)
      : north = max(corner1.latitude, corner2.latitude),
        south = min(corner1.latitude, corner2.latitude),
        east = max(corner1.longitude, corner2.longitude),
        west = min(corner1.longitude, corner2.longitude);

  /// [points] must not be empty
  factory LatLngBounds.fromPoints(Iterable<LatLng> points) {
    assert(points.isNotEmpty, "LatLngBounds needs at least one point");
    final bounds = LatLngBounds(points.first, points.first);
    for (final p in points) {
      bounds.extend(p);
    }
    return bounds;
  }

  LatLng get northEast => LatLng(north, east);
  LatLng get southWest => LatLng(south, west);
  LatLng get northWest => LatLng(north, west);
  LatLng get southEast => LatLng(south, east);
  LatLng get center => LatLng((north + south) / 2, (east + west) / 2);

  void extend(LatLng point) {
    north = max(north, point.latitude);
    south = min(south, point.latitude);
    east = max(east, point.longitude);
    west = min(west, point.longitude);
  }

  bool contains(LatLng point) =>
      point.latitude <= north && point.latitude >= south && point.longitude <= east && point.longitude >= west;

  bool isOverlapping(LatLngBounds other) =>
      !(other.west > east || other.east < west || other.south > north || other.north < south);

  @override
  bool operator ==(Object other) =>
      other is LatLngBounds &&
      other.north == north &&
      other.south == south &&
      other.east == east &&
      other.west == west;

  @override
  int get hashCode => Object.hash(north, south, east, west);

  @override
  String toString() => "LatLngBounds(n: $north, s: $south, e: $east, w: $west)";
}

/// Map zoom levels are based on 512px tiles: the world is `512 * 2^zoom` logical pixels wide.
/// (One zoom level less than the old 256px raster convention for the same scale.)
const double mapWorldTileSize = 512;

/// Web mercator position of [point] in world pixels at zoom 0 ([mapWorldTileSize] wide).
Offset projectMercator(LatLng point, {double worldSize = mapWorldTileSize}) {
  final lat = point.latitude.clamp(-85.05112878, 85.05112878) * pi / 180;
  final x = (point.longitude + 180) / 360 * worldSize;
  final y = (1 - log(tan(lat) + 1 / cos(lat)) / pi) / 2 * worldSize;
  return Offset(x, y);
}

/// Inverse of [projectMercator]
LatLng unprojectMercator(Offset world, {double worldSize = mapWorldTileSize}) {
  final lng = world.dx / worldSize * 360 - 180;
  final n = pi - 2 * pi * world.dy / worldSize;
  final lat = 180 / pi * atan(0.5 * (exp(n) - exp(-n)));
  return LatLng(lat.clamp(-90, 90), ((lng + 180) % 360) - 180);
}

/// Snapshot of the map view: where it looks, and how big it is on screen.
///
/// Matches the map engine's camera model so Flutter overlays (markers, editors) line up with the native map,
/// including rotation ([bearing]), perspective ([tilt]), and 3D terrain ([centerElevation]).
class MapCamera {
  final LatLng center;
  final double zoom;

  /// Degrees clockwise from north that the top of the screen points.
  final double bearing;

  /// Degrees away from looking straight down.
  final double tilt;

  /// Logical size of the map widget
  final Size size;

  /// Ground elevation (meters) at [center] when the map shows 3D terrain. Null on a flat map.
  /// Points are then projected at their own ground height, relative to this.
  final double? centerElevation;

  /// How much taller the 3D terrain is drawn than it really is
  final double terrainExaggeration;

  /// The map engine's vertical field of view (radians)
  static const fov = 0.6435011087932844;

  const MapCamera(
      {required this.center,
      required this.zoom,
      this.bearing = 0,
      this.tilt = 0,
      required this.size,
      this.centerElevation,
      this.terrainExaggeration = 1});

  /// [centerElevation] is kept unless [flat] is set
  MapCamera copyWith(
          {LatLng? center,
          double? zoom,
          double? bearing,
          double? tilt,
          Size? size,
          double? centerElevation,
          double? terrainExaggeration,
          bool flat = false}) =>
      MapCamera(
          center: center ?? this.center,
          zoom: zoom ?? this.zoom,
          bearing: bearing ?? this.bearing,
          tilt: tilt ?? this.tilt,
          size: size ?? this.size,
          centerElevation: flat ? null : centerElevation ?? this.centerElevation,
          terrainExaggeration: terrainExaggeration ?? this.terrainExaggeration);

  double get worldSize => mapWorldTileSize * pow(2, zoom);

  /// Map rotation in radians, in the same sense as [bearing]
  double get bearingRad => bearing * pi / 180;

  double get _cameraToCenterDistance => 0.5 * size.height / tan(fov / 2);

  Offset get _centerWorld => projectMercator(center, worldSize: worldSize);

  /// World pixels per meter of height, at the center of the view
  double get pixelsPerMeter => worldSize / (40075016.686 * cos(center.latitude * pi / 180));

  /// Height (world pixels) of ground at [elevation] meters above the ground at the center of the view
  double _height(double? elevation) => (centerElevation == null || elevation == null)
      ? 0
      : (elevation - centerElevation!) * terrainExaggeration * pixelsPerMeter;

  /// Screen position (logical pixels, relative to the map widget) of [point].
  /// On 3D terrain, pass the ground [elevation] (meters) at the point.
  /// Null when the point is behind the camera.
  Offset? latLngToScreen(LatLng point, {double? elevation}) {
    final ws = worldSize;
    final c = _centerWorld;
    final p = projectMercator(point, worldSize: ws);
    double dx = p.dx - c.dx;
    final dy = p.dy - c.dy;
    // Take the short way around the antimeridian
    if (dx > ws / 2) dx -= ws;
    if (dx < -ws / 2) dx += ws;

    final b = bearingRad;
    final x = dx * cos(b) + dy * sin(b);
    final y = -dx * sin(b) + dy * cos(b);

    final t = tilt * pi / 180;
    final d = _cameraToCenterDistance;
    final h = _height(elevation);
    final depth = d - y * sin(t) - h * cos(t);
    if (depth <= 1e-6) return null;
    return Offset(size.width / 2 + d * x / depth, size.height / 2 + d * (y * cos(t) - h * sin(t)) / depth);
  }

  /// Inverse of [latLngToScreen]. Null when [screen] is above the horizon.
  /// On 3D terrain, [elevationAt] gives the ground height so the point lands on the surface.
  LatLng? screenToLatLng(Offset screen, {double? Function(LatLng point)? elevationAt}) {
    LatLng? result = _screenToHeight(screen, 0);
    if (result == null || centerElevation == null || elevationAt == null) return result;
    // Walk down the ray to the ground: a few rounds converge for any real terrain
    for (int i = 0; i < 4; i++) {
      final elevation = elevationAt(result!);
      if (elevation == null) break;
      final next = _screenToHeight(screen, _height(elevation));
      if (next == null) break;
      result = next;
    }
    return result;
  }

  /// Where the ray through [screen] crosses [height] (world pixels above the ground at the center)
  LatLng? _screenToHeight(Offset screen, double height) {
    final t = tilt * pi / 180;
    final d = _cameraToCenterDistance;
    final a = (screen.dy - size.height / 2) / d;
    final denom = cos(t) + a * sin(t);
    if (denom <= 1e-6) return null;
    final along = (d * cos(t) - height) / denom;
    if (along <= 0) return null;
    final x = (screen.dx - size.width / 2) / d * along;
    final y = d * sin(t) + along * (a * cos(t) - sin(t));

    final b = bearingRad;
    final dx = x * cos(b) - y * sin(b);
    final dy = x * sin(b) + y * cos(b);
    return unprojectMercator(_centerWorld + Offset(dx, dy), worldSize: worldSize);
  }

  bool isOnScreen(LatLng point, {double margin = 0, double? elevation}) {
    final p = latLngToScreen(point, elevation: elevation);
    if (p == null) return false;
    return p.dx >= -margin && p.dy >= -margin && p.dx <= size.width + margin && p.dy <= size.height + margin;
  }

  /// [point] is on screen (give or take [margin]) and, when tilted, not out toward the horizon:
  /// within [maxDistance] times the camera's distance from the center.
  bool isNearView(LatLng point, {double margin = 0, double maxDistance = 3}) {
    if (!isOnScreen(point, margin: margin)) return false;
    final ws = worldSize;
    final offset = projectMercator(point, worldSize: ws) - _centerWorld;
    // Take the short way around the antimeridian
    final dx = offset.dx.abs() > ws / 2 ? ws - offset.dx.abs() : offset.dx;
    return sqrt(dx * dx + offset.dy * offset.dy) <= maxDistance * _cameraToCenterDistance;
  }

  /// Box around everything visible. With tilt, only down to the horizon.
  LatLngBounds get visibleBounds {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    final points = corners.map(screenToLatLng).nonNulls.toList();
    if (points.length < 4) {
      // Top edge is past the horizon. Sample down the sides instead.
      for (double f = 0.1; f <= 1; f += 0.1) {
        points.addAll([Offset(0, size.height * f), Offset(size.width, size.height * f)]
            .map(screenToLatLng)
            .nonNulls
            .take(2));
        if (points.length >= 4) break;
      }
    }
    if (points.isEmpty) return LatLngBounds(center, center);
    return LatLngBounds.fromPoints(points);
  }

  /// Meters per logical pixel at the center of the view
  double get metersPerPixel =>
      40075016.686 * cos(center.latitude * pi / 180) / worldSize;

  /// Camera that shows all of [bounds] in a view of [size], keeping [bearing] and [tilt].
  ///
  /// The fit is computed as if looking straight down. With tilt, the far edge has a bit less room.
  static MapCamera fit(
    LatLngBounds bounds,
    Size size, {
    EdgeInsets padding = EdgeInsets.zero,
    double bearing = 0,
    double tilt = 0,
    double minZoom = 0,
    double maxZoom = 18,
  }) {
    final corners = [bounds.northWest, bounds.northEast, bounds.southEast, bounds.southWest]
        .map((e) => projectMercator(e))
        .toList();
    final b = bearing * pi / 180;
    final rotated = corners.map((p) => Offset(p.dx * cos(b) + p.dy * sin(b), -p.dx * sin(b) + p.dy * cos(b)));
    final w0 = rotated.map((e) => e.dx).reduce(max) - rotated.map((e) => e.dx).reduce(min);
    final h0 = rotated.map((e) => e.dy).reduce(max) - rotated.map((e) => e.dy).reduce(min);

    final availW = max(1.0, size.width - padding.horizontal);
    final availH = max(1.0, size.height - padding.vertical);
    double zoom = maxZoom;
    if (w0 > 0 || h0 > 0) {
      final scale = min(w0 > 0 ? availW / w0 : double.infinity, h0 > 0 ? availH / h0 : double.infinity);
      zoom = log(scale) / ln2;
    }
    zoom = zoom.clamp(minZoom, maxZoom).toDouble();

    // Center of the bounds, shifted for uneven padding
    final ws = mapWorldTileSize * pow(2, zoom);
    final centerWorld = corners.reduce((a, c) => a + c) / 4 * (ws / mapWorldTileSize);
    final shift = Offset((padding.right - padding.left) / 2, (padding.bottom - padding.top) / 2);
    final shiftWorld = Offset(shift.dx * cos(b) - shift.dy * sin(b), shift.dx * sin(b) + shift.dy * cos(b));
    return MapCamera(
        center: unprojectMercator(centerWorld + shiftWorld, worldSize: ws),
        zoom: zoom,
        bearing: bearing,
        tilt: tilt,
        size: size);
  }

  @override
  bool operator ==(Object other) =>
      other is MapCamera &&
      other.center == center &&
      other.zoom == zoom &&
      other.bearing == bearing &&
      other.tilt == tilt &&
      other.size == size &&
      other.centerElevation == centerElevation &&
      other.terrainExaggeration == terrainExaggeration;

  @override
  int get hashCode => Object.hash(center, zoom, bearing, tilt, size, centerElevation, terrainExaggeration);

  @override
  String toString() =>
      "MapCamera($center, z$zoom, bearing $bearing, tilt $tilt, $size, elev $centerElevation x$terrainExaggeration)";
}

/// Fractional slippy-map tile coordinate of [p] at tile zoom [z] (256px or 512px tiles alike).
(double, double) tileXY(LatLng p, int z) {
  final n = (1 << z).toDouble();
  final lat = p.latitude.clamp(-85.05112878, 85.05112878) * pi / 180;
  final x = (p.longitude + 180) / 360 * n;
  final y = (1 - log(tan(lat) + 1 / cos(lat)) / pi) / 2 * n;
  return (x.clamp(0, n - 1e-9), y.clamp(0, n - 1e-9));
}

/// North west corner of a slippy-map tile
LatLng tileToLatLng(int x, int y, int z) =>
    unprojectMercator(Offset(x.toDouble(), y.toDouble()), worldSize: (1 << z).toDouble());
