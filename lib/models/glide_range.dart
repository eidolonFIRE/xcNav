import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/dem_service.dart' show demZoomLevels;

/// Ground elevation (meters MSL) at [latlng], sampled from DEM tiles at [zoom]. Null when not loaded yet.
typedef GroundSampler = double? Function(LatLng latlng, int zoom);

/// Meters per degree of latitude. (Same earth radius as latlong2's `Distance`)
const double _metersPerDegLat = pi * 6371009 / 180;

/// Smallest grid cell (meters). Used while low.
const double glideMinCellSize = 50;

/// Grid cells from the pilot to the grid edge. Cells get bigger as the pilot gets higher.
const int glideCellsPerRadius = 50;

/// Farthest the grid reaches from the pilot (meters).
const double glideMaxRadius = 50000;

/// Closest the grid edge can be to the pilot (meters).
const double glideMinRadius = 200;

/// Live glide ratios outside of 1:1 to this aren't a glide. (Nearly level flight under power reads as a huge
/// glide ratio.)
const double maxGlideRatio = 12;

enum GlideRangeMode {
  /// Hidden
  off,

  /// Only while on a glide
  auto,

  /// Always shown. Uses the default glide ratio when not on a glide.
  always,
}

/// Grid cell size (meters) for a grid reaching [radius] meters from the pilot.
double glideCellSizeFor(double radius) => max(glideMinCellSize, radius / glideCellsPerRadius);

/// Coarsest DEM zoom with at least 2 pixels per [cellSize].
int glideDemZoomFor(double cellSize, double latitude) {
  for (final zoom in demZoomLevels) {
    final pixelSize = 2 * pi * 6378137 * cos(latitude * pi / 180) / (256 * pow(2, zoom));
    if (pixelSize <= cellSize / 2) return zoom;
  }
  return demZoomLevels.last;
}

/// Still-air glide ratio from the live vario and speed.
///
/// Uses [airspeed] (from the wind solver) when known, otherwise ground [speed].
/// Null when not on a glide: climbing, level, or outside 1:1 to [maxGlideRatio].
double? liveGlideRatio({required double vario, required double speed, double? airspeed}) {
  final sink = -vario;
  if (sink < 0.1) return null;
  final ratio = (airspeed ?? speed) / sink;
  if (!ratio.isFinite || ratio < 1 || ratio > maxGlideRatio) return null;
  return ratio;
}

/// Glide ratio to draw the glide range with, or null to hide it.
double? glideRatioForMode(GlideRangeMode mode, {required double? live, required double defaultRatio}) => switch (mode) {
      GlideRangeMode.off => null,
      GlideRangeMode.auto => live,
      GlideRangeMode.always => live ?? defaultRatio,
    };

class GlideWind {
  /// m/s
  final double airspeed;

  /// m/s
  final double windSpd;

  /// Radians. Direction the wind blows toward.
  final double windHdg;

  const GlideWind({required this.airspeed, required this.windSpd, required this.windHdg});
}

class GlideRangeParams {
  /// Pilot altitude (meters MSL)
  final double alt;

  /// Still-air glide ratio
  final double glideRatio;

  /// Height (meters) to still have over the ground on arrival
  final double margin;

  final GlideWind? wind;

  const GlideRangeParams({required this.alt, required this.glideRatio, required this.margin, this.wind});

  /// Glide ratio over the ground flying toward [bearing] (radians). 0 when the wind won't allow any progress.
  double groundGlideRatio(double bearing) {
    final w = wind;
    if (w == null || w.airspeed <= 0) return glideRatio;
    final rel = bearing - w.windHdg;
    final along = w.windSpd * cos(rel);
    final cross = w.windSpd * sin(rel);
    if (cross.abs() >= w.airspeed) return 0;
    final groundSpeed = sqrt(w.airspeed * w.airspeed - cross * cross) + along;
    if (groundSpeed <= 0) return 0;
    return glideRatio * groundSpeed / w.airspeed;
  }

  /// Best glide ratio over the ground in any direction (straight downwind).
  double get maxGroundGlideRatio {
    final w = wind;
    if (w == null || w.airspeed <= 0) return glideRatio;
    return glideRatio * (w.airspeed + w.windSpd) / w.airspeed;
  }

  /// First guess for how far the grid should reach, given [agl] (meters) at the pilot.
  double initialRadius(double agl) =>
      ((agl - margin) * maxGroundGlideRatio * 1.2).clamp(glideMinRadius, glideMaxRadius).toDouble();
}

/// Square grid of ground elevations centered on the pilot. Row 0 is north, column 0 is west.
class GlideGrid {
  final LatLng origin;

  /// Meters
  final double cellSize;

  /// Cells from the center cell to the edge
  final int halfSize;

  /// Meters MSL, row-major. NaN where the DEM isn't loaded.
  final Float32List ground;

  GlideGrid({required this.origin, required this.cellSize, required this.halfSize, required this.ground})
      : assert(ground.length == (2 * halfSize + 1) * (2 * halfSize + 1));

  /// Cells per side
  int get size => 2 * halfSize + 1;

  double get _dLat => cellSize / _metersPerDegLat;
  double get _dLng => cellSize / (_metersPerDegLat * cos(origin.latitude * pi / 180));

  LatLng cellCenter(int row, int col) =>
      LatLng(origin.latitude + (halfSize - row) * _dLat, origin.longitude + (col - halfSize) * _dLng);

  /// Outer edges of the grid
  LatLngBounds get bounds => LatLngBounds(
        LatLng(origin.latitude - (halfSize + 0.5) * _dLat, origin.longitude - (halfSize + 0.5) * _dLng),
        LatLng(origin.latitude + (halfSize + 0.5) * _dLat, origin.longitude + (halfSize + 0.5) * _dLng),
      );

  /// Sample the ground at the center of each cell of a grid reaching [radius] meters from [origin].
  factory GlideGrid.sample(LatLng origin, double radius, GroundSampler sampler) {
    final cellSize = glideCellSizeFor(radius);
    final halfSize = max(1, (radius / cellSize).ceil());
    final zoom = glideDemZoomFor(cellSize, origin.latitude);
    final n = 2 * halfSize + 1;
    final grid = GlideGrid(origin: origin, cellSize: cellSize, halfSize: halfSize, ground: Float32List(n * n));
    for (int row = 0; row < n; row++) {
      for (int col = 0; col < n; col++) {
        grid.ground[row * n + col] = sampler(grid.cellCenter(row, col), zoom) ?? double.nan;
      }
    }
    return grid;
  }
}

class GlideRange {
  final GlideGrid grid;
  final GlideRangeParams params;

  /// Meters above (ground + margin) on arrival, row-major. NaN where unreachable.
  final Float32List excess;

  /// 1 where the glide was cut short because the ground isn't loaded yet.
  final Uint8List unknown;

  /// Reachable cells touch the grid edge, so the grid was too small.
  final bool touchesEdge;

  /// Some of the glide was cut short because the ground isn't loaded yet.
  final bool hasUnknown;

  GlideRange(
      {required this.grid,
      required this.params,
      required this.excess,
      required this.unknown,
      required this.touchesEdge,
      required this.hasUnknown});

  bool isReachable(int row, int col) => !excess[row * grid.size + col].isNaN;
}

/// Moves to neighboring cells: 8 neighbors plus 8 knight moves, so paths can head within ~3° of any direction.
const List<(int, int)> _moves = [
  (-1, 0), (1, 0), (0, -1), (0, 1), //
  (-1, -1), (-1, 1), (1, -1), (1, 1), //
  (-2, -1), (-2, 1), (2, -1), (2, 1), //
  (-1, -2), (-1, 2), (1, -2), (1, 2),
];

/// Max-heap of (altitude, cell index) in typed arrays, so the search doesn't allocate a record per push.
class _AltHeap {
  Float64List _alts;
  Int32List _cells;
  int length = 0;

  _AltHeap(int capacity)
      : _alts = Float64List(capacity),
        _cells = Int32List(capacity);

  bool get isNotEmpty => length > 0;

  /// Altitude of the top entry. Read before [pop].
  double get topAlt => _alts[0];
  int get topCell => _cells[0];

  void push(double alt, int cell) {
    if (length == _alts.length) {
      _alts = Float64List(length * 2)..setRange(0, length, _alts);
      _cells = Int32List(length * 2)..setRange(0, length, _cells);
    }
    int i = length++;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_alts[parent] >= alt) break;
      _alts[i] = _alts[parent];
      _cells[i] = _cells[parent];
      i = parent;
    }
    _alts[i] = alt;
    _cells[i] = cell;
  }

  void pop() {
    length--;
    if (length == 0) return;
    final alt = _alts[length];
    final cell = _cells[length];
    int i = 0;
    while (true) {
      int child = 2 * i + 1;
      if (child >= length) break;
      if (child + 1 < length && _alts[child + 1] > _alts[child]) child++;
      if (_alts[child] <= alt) break;
      _alts[i] = _alts[child];
      _cells[i] = _cells[child];
      i = child;
    }
    _alts[i] = alt;
    _cells[i] = cell;
  }
}

/// Find the most altitude the pilot can have over each cell, taking any route.
///
/// Best-first search from the pilot's cell: the cell with the most altitude left expands first. A cell is only
/// reachable if the pilot arrives at least `margin` above its ground, so routes go around ridges and through valleys.
GlideRange solveGlideRange(GlideGrid grid, GlideRangeParams params) {
  final n = grid.size;
  final ground = grid.ground;
  final margin = params.margin;

  // Per usable move: row/col step, altitude lost, and for knight moves the two cells passed over on the way.
  // Moves the wind won't allow are dropped.
  final moveDr = <int>[], moveDc = <int>[], moveA = <int>[], moveB = <int>[];
  final moveLoss = <double>[];
  for (final (dr, dc) in _moves) {
    final ratio = params.groundGlideRatio(atan2(dc.toDouble(), -dr.toDouble()));
    if (ratio <= 0) continue;
    moveDr.add(dr);
    moveDc.add(dc);
    moveLoss.add(grid.cellSize * sqrt(dr * dr + dc * dc) / ratio);
    if (dr.abs() == 2) {
      moveA.add(dr.sign * n);
      moveB.add(dr.sign * n + dc);
    } else if (dc.abs() == 2) {
      moveA.add(dc.sign);
      moveB.add(dr * n + dc.sign);
    } else {
      moveA.add(0);
      moveB.add(0);
    }
  }

  final best = Float64List(n * n)..fillRange(0, n * n, double.negativeInfinity);
  final done = Uint8List(n * n);
  final unknown = Uint8List(n * n);
  bool hasUnknown = false;

  final start = grid.halfSize * n + grid.halfSize;
  best[start] = params.alt;
  final queue = _AltHeap(4 * n * n);
  queue.push(params.alt, start);

  /// Ground at a cell the glide passes over clears it. Marks unloaded ground.
  bool clears(int index, double alt) {
    final g = ground[index];
    if (g.isNaN) {
      unknown[index] = 1;
      hasUnknown = true;
      return false;
    }
    return alt >= g + margin;
  }

  while (queue.isNotEmpty) {
    final alt = queue.topAlt;
    final index = queue.topCell;
    queue.pop();
    if (done[index] == 1) continue;
    done[index] = 1;
    final row = index ~/ n;
    final col = index % n;

    for (int k = 0; k < moveLoss.length; k++) {
      final r = row + moveDr[k];
      final c = col + moveDc[k];
      if (r < 0 || r >= n || c < 0 || c >= n) continue;
      final target = r * n + c;
      if (done[target] == 1) continue;

      final loss = moveLoss[k];
      final arrive = alt - loss;
      if (arrive <= best[target]) continue;

      // Knight moves pass over two other cells on the way
      final a = moveA[k];
      if (a != 0) {
        final mid = alt - loss / 2;
        if (!clears(index + a, mid) || !clears(index + moveB[k], mid)) continue;
      }

      if (!clears(target, arrive)) continue;
      best[target] = arrive;
      queue.push(arrive, target);
    }
  }

  final excess = Float32List(n * n);
  bool touchesEdge = false;
  for (int i = 0; i < n * n; i++) {
    final e = best[i] - ground[i] - margin;
    if (best[i].isFinite && !e.isNaN && e >= 0) {
      excess[i] = e;
      final row = i ~/ n;
      final col = i % n;
      if (row == 0 || col == 0 || row == n - 1 || col == n - 1) touchesEdge = true;
    } else {
      excess[i] = double.nan;
    }
  }

  return GlideRange(
      grid: grid, params: params, excess: excess, unknown: unknown, touchesEdge: touchesEdge, hasUnknown: hasUnknown);
}
