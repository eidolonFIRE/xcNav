import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/glide_range.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/services/glide_range_service.dart';
import 'package:xcnav/views/map/glide_range_layer.dart';

const origin = LatLng(40, -105);
const metersPerDegLat = pi * 6371009 / 180;

/// Meters east and north of [origin]
(double, double) toMeters(LatLng latlng) => (
      (latlng.longitude - origin.longitude) * metersPerDegLat * cos(origin.latitude * pi / 180),
      (latlng.latitude - origin.latitude) * metersPerDegLat,
    );

GroundSampler terrain(double? Function(double east, double north) elev) => (latlng, zoom) {
      final (east, north) = toMeters(latlng);
      return elev(east, north);
    };

final flat = terrain((e, n) => 0);

/// Excess height at the cell nearest [east], [north] meters from the pilot. Null if unreachable.
double? excessAt(GlideRange range, double east, double north) {
  final grid = range.grid;
  final row = grid.halfSize - (north / grid.cellSize).round();
  final col = grid.halfSize + (east / grid.cellSize).round();
  final e = range.excess[row * grid.size + col];
  return e.isNaN ? null : e;
}

GlideRange solve(GroundSampler sampler,
    {double alt = 1050, double glideRatio = 5, double margin = 50, GlideWind? wind, double radius = 6000}) {
  final params = GlideRangeParams(alt: alt, glideRatio: glideRatio, margin: margin, wind: wind);
  return solveGlideRange(GlideGrid.sample(origin, radius, sampler), params);
}

void main() {
  group("grid sizing", () {
    test("cells grow with radius", () {
      expect(glideCellSizeFor(1000), glideMinCellSize);
      expect(glideCellSizeFor(8000), 200);
      expect(glideCellSizeFor(40000), 1000);
    });

    test("coarser DEM for bigger cells", () {
      expect(glideDemZoomFor(40, 40), 12);
      expect(glideDemZoomFor(120, 40), 11);
      expect(glideDemZoomFor(250, 40), 10);
      expect(glideDemZoomFor(500, 40), 9);
    });

    test("grid never exceeds 40 cells from the pilot", () {
      for (final radius in [200.0, 3000.0, 10000.0, 50000.0]) {
        final grid = GlideGrid.sample(origin, radius, flat);
        expect(grid.halfSize, lessThanOrEqualTo(glideCellsPerRadius));
        expect(grid.halfSize * grid.cellSize, greaterThanOrEqualTo(radius - 1));
      }
    });

    test("samples cell centers only", () {
      int calls = 0;
      final grid = GlideGrid.sample(origin, 1000, (latlng, zoom) {
        calls++;
        return 0;
      });
      expect(calls, grid.size * grid.size);
    });
  });

  group("liveGlideRatio", () {
    test("climbing or level isn't a glide", () {
      expect(liveGlideRatio(vario: 1, speed: 10), isNull);
      expect(liveGlideRatio(vario: 0, speed: 10), isNull);
    });

    test("sinking uses the live ratio", () {
      expect(liveGlideRatio(vario: -1, speed: 8), 8);
    });

    test("prefers airspeed when known", () {
      expect(liveGlideRatio(vario: -1, speed: 14, airspeed: 9), 9);
    });

    test("only 1:1 to 12:1 is a glide", () {
      expect(liveGlideRatio(vario: -1, speed: 1), 1);
      expect(liveGlideRatio(vario: -1, speed: 12), 12);
      expect(liveGlideRatio(vario: -10, speed: 9), isNull);
      expect(liveGlideRatio(vario: -0.2, speed: 15), isNull);
    });
  });

  group("glideRatioForMode", () {
    test("off never shows", () {
      expect(glideRatioForMode(GlideRangeMode.off, live: 8, defaultRatio: 5), isNull);
      expect(glideRatioForMode(GlideRangeMode.off, live: null, defaultRatio: 5), isNull);
    });

    test("auto only shows on a glide", () {
      expect(glideRatioForMode(GlideRangeMode.auto, live: 8, defaultRatio: 5), 8);
      expect(glideRatioForMode(GlideRangeMode.auto, live: null, defaultRatio: 5), isNull);
    });

    test("always falls back to the default", () {
      expect(glideRatioForMode(GlideRangeMode.always, live: 8, defaultRatio: 5), 8);
      expect(glideRatioForMode(GlideRangeMode.always, live: null, defaultRatio: 5), 5);
    });
  });

  group("solveGlideRange", () {
    test("flat ground reaches AGL x glide ratio", () {
      // 1000m usable height at 5:1 -> 5000m
      final range = solve(flat);
      expect(range.touchesEdge, false);
      expect(range.hasUnknown, false);
      for (final (e, n) in [(4600.0, 0.0), (-4600.0, 0.0), (0.0, 4600.0), (3250.0, 3250.0), (-3250.0, -3250.0)]) {
        expect(excessAt(range, e, n), isNotNull, reason: "($e, $n)");
      }
      for (final (e, n) in [(5400.0, 0.0), (0.0, -5400.0), (3820.0, 3820.0)]) {
        expect(excessAt(range, e, n), isNull, reason: "($e, $n)");
      }
      // Excess shrinks with distance
      expect(excessAt(range, 0, 0), closeTo(1000, 1));
      expect(excessAt(range, 2550, 0), closeTo(490, 1));
    });

    test("goes through a gap in a wall", () {
      // Tall wall 1000m east, with a gap around the pilot's latitude
      final range = solve(terrain((e, n) => (e > 925 && e < 1075 && n.abs() > 100) ? 5000 : 0));
      expect(excessAt(range, 1500, 0), isNotNull);
      final behind = excessAt(range, 1500, 1500);
      final inFront = excessAt(range, -1500, 1500);
      expect(behind, isNotNull);
      // The route through the gap is longer than the straight line on the open side
      expect(behind!, lessThan(inFront! - 40));
    });

    test("can't cross a ridge that's too high", () {
      final range = solve(terrain((e, n) => (e > 925 && e < 1075) ? 2000 : 0));
      expect(excessAt(range, 1500, 0), isNull);
      expect(excessAt(range, 1500, 2000), isNull);
      expect(excessAt(range, -1500, 0), isNotNull);
    });

    test("clears a ridge that's low enough", () {
      // At 1000m out the pilot has ~800m. Ridge at 600m + 50m margin is clear.
      final range = solve(terrain((e, n) => (e > 925 && e < 1075) ? 600 : 0));
      expect(excessAt(range, 1500, 0), isNotNull);
    });

    test("ridge doesn't sneak through knight moves", () {
      // Ridge one cell thick
      final sampler = terrain((e, n) => (e > 1020 && e < 1080) ? 2000 : 0);
      final range = solve(sampler, radius: 3000);
      expect(range.grid.cellSize, glideMinCellSize);
      expect(excessAt(range, 1500, 0), isNull);
      expect(excessAt(range, 1500, 700), isNull);
    });

    test("higher ground ends the glide sooner", () {
      final range = solve(terrain((e, n) => e > 0 ? e * 0.1 : 0));
      expect(excessAt(range, -4600, 0), isNotNull);
      // Ground rising at 1:10 against a 1:5 glide meets at 1000 / (0.2 + 0.1)
      expect(excessAt(range, 3000, 0), isNotNull);
      expect(excessAt(range, 3600, 0), isNull);
    });

    test("wind stretches the range downwind", () {
      // 10 m/s airspeed, 5 m/s wind blowing toward the east
      const wind = GlideWind(airspeed: 10, windSpd: 5, windHdg: pi / 2);
      final range = solve(flat, wind: wind, radius: 9000);
      expect(excessAt(range, 7000, 0), isNotNull);
      expect(excessAt(range, -2200, 0), isNotNull);
      expect(excessAt(range, -2900, 0), isNull);
    });

    test("headwind stronger than airspeed blocks upwind", () {
      const wind = GlideWind(airspeed: 10, windSpd: 15, windHdg: pi / 2);
      final range = solve(flat, wind: wind, radius: 14000);
      expect(excessAt(range, 10000, 0), isNotNull);
      expect(excessAt(range, -500, 0), isNull);
      expect(excessAt(range, 0, 2000), isNull);
    });

    test("unloaded ground blocks the glide and is marked", () {
      final range = solve(terrain((e, n) => e > 1000 ? null : 0));
      expect(range.hasUnknown, true);
      expect(excessAt(range, 1500, 0), isNull);
      final grid = range.grid;
      final col = grid.halfSize + (1040 / grid.cellSize).round();
      expect(range.unknown[grid.halfSize * grid.size + col], 1);
      expect(excessAt(range, -1500, 0), isNotNull);
    });

    test("flags a grid that's too small", () {
      expect(solve(flat, radius: 2000).touchesEdge, true);
    });
  });

  group("GlideRangeService", () {
    Geo geoAt(double alt, {double ground = 0, LatLng latlng = origin}) =>
        Geo(lat: latlng.latitude, lng: latlng.longitude, alt: alt)..ground = ground;

    GlideRangeService makeService(GroundSampler sampler, List<double> radii) => GlideRangeService(
        sampler: sampler,
        solver: (grid, params) async {
          radii.add(grid.halfSize * grid.cellSize);
          return solveGlideRange(grid, params);
        });

    test("grows the grid until the range fits", () async {
      final radii = <double>[];
      // Low ground past 1km: the first guess from the ground below is too small
      final service = makeService(terrain((e, n) => e > 1000 ? -400 : 0), radii);
      service.update(geoAt(300), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
      await pumpEventQueue();
      expect(radii.length, greaterThan(1));
      expect(radii, orderedEquals([...radii]..sort()));
      expect(service.range.value, isNotNull);
      expect(service.range.value!.touchesEdge, false);
    });

    test("nothing below the margin", () async {
      final service = makeService(flat, []);
      service.update(geoAt(40), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
      await pumpEventQueue();
      expect(service.range.value, isNull);
    });

    test("clears once below the margin", () async {
      final service = makeService(flat, []);
      service.update(geoAt(500), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
      await pumpEventQueue();
      expect(service.range.value, isNotNull);
      service.update(geoAt(30), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
      expect(service.range.value, isNull);
    });

    test("throttles and recomputes after moving", () async {
      final radii = <double>[];
      final service = makeService(flat, radii);
      var now = DateTime(2026, 1, 1, 12);
      await withClock(Clock(() => now), () async {
        service.update(geoAt(500), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
        await pumpEventQueue();
        final runs = radii.length;

        // Too soon
        now = now.add(const Duration(seconds: 1));
        service.update(geoAt(800), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
        await pumpEventQueue();
        expect(radii.length, runs);

        // Hasn't moved
        now = now.add(const Duration(seconds: 5));
        service.update(geoAt(505), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
        await pumpEventQueue();
        expect(radii.length, runs);

        // Climbed
        service.update(geoAt(800), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
        await pumpEventQueue();
        expect(radii.length, greaterThan(runs));
      });
    });

    test("unloaded ground recomputes only once more tiles load", () async {
      final radii = <double>[];
      int tiles = 0;
      final service = GlideRangeService(
          sampler: terrain((e, n) => e > 500 ? null : 0),
          tilesLoaded: () => tiles,
          solver: (grid, params) async {
            radii.add(grid.halfSize * grid.cellSize);
            return solveGlideRange(grid, params);
          });
      var now = DateTime(2026, 1, 1, 12);
      await withClock(Clock(() => now), () async {
        service.update(geoAt(500), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
        await pumpEventQueue();
        expect(service.range.value!.hasUnknown, true);
        final runs = radii.length;

        // No new tiles
        now = now.add(const Duration(seconds: 5));
        service.update(geoAt(500), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
        await pumpEventQueue();
        expect(radii.length, runs);

        // A tile loaded
        tiles++;
        now = now.add(const Duration(seconds: 5));
        service.update(geoAt(500), vario: 0, speed: 10, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
        await pumpEventQueue();
        expect(radii.length, greaterThan(runs));
      });
    });

    test("auto hides when not on a glide", () async {
      final service = makeService(flat, []);
      service.update(geoAt(500), vario: -1, speed: 10, mode: GlideRangeMode.auto, defaultRatio: 5, margin: 50);
      await pumpEventQueue();
      expect(service.range.value, isNotNull);
      service.update(geoAt(500), vario: -0.5, speed: 10, mode: GlideRangeMode.auto, defaultRatio: 5, margin: 50);
      expect(service.range.value, isNull);
      service.update(geoAt(500), vario: 1, speed: 10, mode: GlideRangeMode.auto, defaultRatio: 5, margin: 50);
      expect(service.range.value, isNull);
    });

    test("always uses the default when climbing or better than 12:1", () async {
      final ratios = <double>[];
      var now = DateTime(2026, 1, 1, 12);
      final service = GlideRangeService(
          sampler: flat,
          solver: (grid, params) async {
            ratios.add(params.glideRatio);
            return solveGlideRange(grid, params);
          });
      await withClock(Clock(() => now), () async {
        service.update(geoAt(500), vario: 1, speed: 10, mode: GlideRangeMode.always, defaultRatio: 6, margin: 50);
        await pumpEventQueue();
        expect(ratios.last, 6);
        now = now.add(const Duration(seconds: 30));
        service.update(geoAt(500), vario: -0.5, speed: 10, mode: GlideRangeMode.always, defaultRatio: 6, margin: 50);
        await pumpEventQueue();
        expect(ratios.last, 6);
        expect(service.range.value, isNotNull);
      });
    });

    test("off shows nothing", () async {
      final service = makeService(flat, []);
      service.update(geoAt(500), vario: -1, speed: 10, mode: GlideRangeMode.off, defaultRatio: 5, margin: 50);
      await pumpEventQueue();
      expect(service.range.value, isNull);
    });

    test("uses wind and live glide ratio", () async {
      GlideRangeParams? used;
      final service = GlideRangeService(
          sampler: flat,
          solver: (grid, params) async {
            used = params;
            return solveGlideRange(grid, params);
          });
      final wind = WindSolveResult(9, 3, pi, Offset.zero, 0, [], [], DateTime(2026));
      service.update(geoAt(500),
          vario: -1, speed: 12, wind: wind, mode: GlideRangeMode.always, defaultRatio: 5, margin: 50);
      await pumpEventQueue();
      expect(used!.glideRatio, 9);
      expect(used!.wind!.windSpd, 3);
      expect(used!.wind!.windHdg, pi);
    });
  });

  group("glideRangePixels", () {
    test("edge dark, center clear, unreachable clear, unknown grey", () {
      final range = solve(terrain((e, n) => e > 1000 ? null : 0));
      final pixels = glideRangePixels(range, edgeColor: Colors.pink, innerColor: Colors.yellow);
      final grid = range.grid;
      int alphaAt(double east, double north) {
        final row = grid.halfSize - (north / grid.cellSize).round();
        final col = grid.halfSize + (east / grid.cellSize).round();
        return pixels[(row * grid.size + col) * 4 + 3];
      }

      // Center has plenty of height, so it's faded out
      expect(alphaAt(0, 0), 0);
      expect(alphaAt(-4800, 0), greaterThan(0));
      expect(alphaAt(-4000, 0), 0);
      expect(alphaAt(-4950, 0), greaterThan(100));
      expect(alphaAt(-5900, 0), 0);
      expect(alphaAt(1040, 0), greaterThan(0));

      // Premultiplied: color never exceeds alpha, and is black where clear
      for (int i = 0; i < pixels.length; i += 4) {
        for (int c = 0; c < 3; c++) {
          expect(pixels[i + c], lessThanOrEqualTo(pixels[i + 3]));
        }
      }
    });

    test("shades from edge color toward inner color", () {
      const edge = Color(0xff0000ff);
      const inner = Color(0xffff0000);
      final range = solve(flat);
      final pixels = glideRangePixels(range, edgeColor: edge, innerColor: inner);
      final dist = glideEdgeDistance(range);
      final grid = range.grid;
      final row = grid.halfSize;
      // Walk in from the west edge
      int col = 0;
      while (dist[row * grid.size + col] != 1) {
        col++;
      }
      final i = (row * grid.size + col) * 4;
      expect(pixels[i], 0);
      expect(pixels[i + 2], pixels[i + 3]);

      final j = (row * grid.size + col + 3) * 4;
      expect(pixels[j + 3], greaterThan(0));
      expect(pixels[j], greaterThan(0));
      expect(pixels[j + 2], lessThan(pixels[j + 3]));
    });
  });

  test("fade is the same number of cells wide at any cell size", () {
    int fadingCells(GlideRange range) {
      final pixels = glideRangePixels(range, edgeColor: Colors.pink, innerColor: Colors.yellow);
      final grid = range.grid;
      int count = 0;
      for (int col = 0; col < grid.size; col++) {
        final alpha = pixels[(grid.halfSize * grid.size + col) * 4 + 3];
        if (alpha > 0 && range.isReachable(grid.halfSize, col)) count++;
      }
      return count;
    }

    final small = solve(flat, radius: 6000);
    final big = solve(flat, alt: 2050, radius: 12000);
    expect(big.grid.cellSize, 2 * small.grid.cellSize);
    expect(fadingCells(big), closeTo(fadingCells(small), 2));
    expect(fadingCells(small), greaterThan(6));
  });

  test("fade is the same width upwind and downwind", () {
    // Wind blowing east stretches the range east
    final range = solve(flat, wind: const GlideWind(airspeed: 10, windSpd: 4, windHdg: pi / 2), radius: 10000);
    final pixels = glideRangePixels(range, edgeColor: Colors.pink, innerColor: Colors.yellow);
    final grid = range.grid;
    final row = grid.halfSize;
    int fadingCells(Iterable<int> cols) =>
        cols.where((col) => range.isReachable(row, col) && pixels[(row * grid.size + col) * 4 + 3] > 0).length;

    final west = fadingCells([for (int col = 0; col < grid.halfSize; col++) col]);
    final east = fadingCells([for (int col = grid.halfSize + 1; col < grid.size; col++) col]);
    expect(west, greaterThan(3));
    expect(east, closeTo(west, 1));
  });

  test("edge distance counts cells to the nearest unreachable cell", () {
    final range = solve(flat);
    final dist = glideEdgeDistance(range);
    final grid = range.grid;
    final center = grid.halfSize * grid.size + grid.halfSize;
    // 1050m AGL less 50m margin at 5:1 reaches 5000m
    expect(dist[center], closeTo(5000 / grid.cellSize, 1));
    expect(dist[0], 0);
  });

  test("full size grid solves quickly", () {
    final grid = GlideGrid.sample(origin, 40000, terrain((e, n) => 300 * sin(e / 3000) * cos(n / 2000)));
    final stopwatch = Stopwatch()..start();
    final range = solveGlideRange(grid, const GlideRangeParams(alt: 3000, glideRatio: 8, margin: 50));
    final reachable = range.excess.where((e) => !e.isNaN).length;
    debugPrint("Solved ${grid.size}x${grid.size} ($reachable reachable) in ${stopwatch.elapsedMilliseconds}ms");
    expect(reachable, greaterThan(500));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
