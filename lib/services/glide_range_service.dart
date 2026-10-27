import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/glide_range.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/util.dart';

typedef GlideRangeSolver = Future<GlideRange> Function(GlideGrid grid, GlideRangeParams params);

GlideRange _solve((GlideGrid, GlideRangeParams) args) => solveGlideRange(args.$1, args.$2);

int _demTilesLoaded() => demTilesLoaded;

Future<GlideRange> _solveInBackground(GlideGrid grid, GlideRangeParams params) => compute(_solve, (grid, params));

/// Area the pilot can glide to from where they are now.
///
/// Fed by the map's glide range layer, so it only runs while that layer is shown.
class GlideRangeService {
  /// Latest reachable area. Null when there's nothing to show.
  final ValueNotifier<GlideRange?> range = ValueNotifier(null);

  /// Never recompute more often than this.
  static const minInterval = Duration(seconds: 2);

  /// Recompute at least this often (wind and terrain tiles change).
  static const maxInterval = Duration(seconds: 20);

  /// Times to grow the grid when the reachable area runs off its edge.
  static const maxGrowSteps = 3;

  final GroundSampler sampler;
  final GlideRangeSolver solver;

  /// Count of DEM tiles loaded so far. See [demTilesLoaded].
  final int Function() tilesLoaded;

  GlideRangeService(
      {this.sampler = sampleDemAtZoom, this.solver = _solveInBackground, this.tilesLoaded = _demTilesLoaded});

  bool _busy = false;

  /// Bumped on [clear] so a run that finishes afterward is dropped.
  int _generation = 0;

  DateTime? _lastRun;
  LatLng? _lastLatLng;
  double? _lastAlt;
  double? _lastRatio;
  int? _lastTilesLoaded;

  void clear() {
    _generation++;
    _lastRun = null;
    range.value = null;
  }

  /// Recompute if the pilot has moved enough since the last run.
  ///
  /// [margin] is meters. [defaultRatio] is used in [GlideRangeMode.always] when not on a glide.
  void update(Geo? geo,
      {required double vario,
      required double speed,
      WindSolveResult? wind,
      required GlideRangeMode mode,
      required double defaultRatio,
      required double margin}) {
    final ground = geo?.ground;
    final glideRatio = glideRatioForMode(mode,
        live: liveGlideRatio(vario: vario, speed: speed, airspeed: wind?.airspeed), defaultRatio: defaultRatio);
    if (geo == null || ground == null || geo.alt - ground <= margin || glideRatio == null) {
      if (_lastRun != null || range.value != null) clear();
      return;
    }
    if (_busy) return;

    final now = clock.now();
    if (!_isStale(now, geo, glideRatio)) return;

    _lastRun = now;
    _lastLatLng = geo.latlng;
    _lastAlt = geo.alt;
    _lastRatio = glideRatio;
    _lastTilesLoaded = tilesLoaded();

    final params = GlideRangeParams(
        alt: geo.alt,
        glideRatio: glideRatio,
        margin: margin,
        wind: wind == null ? null : GlideWind(airspeed: wind.airspeed, windSpd: wind.windSpd, windHdg: wind.windHdg));

    _busy = true;
    _run(geo.latlng, params.initialRadius(geo.alt - ground), params).whenComplete(() => _busy = false);
  }

  bool _isStale(DateTime now, Geo geo, double glideRatio) {
    if (_lastRun == null) return true;
    final elapsed = now.difference(_lastRun!);
    if (elapsed < minInterval) return false;
    final prev = range.value;
    if (prev == null || elapsed > maxInterval) return true;
    // Unloaded ground only changes once more tiles load
    if (prev.hasUnknown && tilesLoaded() != _lastTilesLoaded) return true;
    return latlngCalc.distance(_lastLatLng!, geo.latlng) > 2 * prev.grid.cellSize ||
        (geo.alt - _lastAlt!).abs() > 20 ||
        (glideRatio - _lastRatio!).abs() > _lastRatio! * 0.1;
  }

  Future<void> _run(LatLng origin, double radius, GlideRangeParams params) async {
    final generation = _generation;
    try {
      GlideRange? result;
      for (int step = 0; step <= maxGrowSteps; step++) {
        result = await solver(GlideGrid.sample(origin, radius, sampler), params);
        if (!result.touchesEdge || radius >= glideMaxRadius) break;
        radius = min(glideMaxRadius, radius * 1.6);
      }
      if (generation == _generation) range.value = result;
    } catch (err, trace) {
      debugPrint("Glide range failed: $err\n$trace");
    }
  }
}

final glideRangeService = GlideRangeService();
