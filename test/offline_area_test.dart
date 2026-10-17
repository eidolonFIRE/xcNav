import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/models/offline_area.dart';

OfflineArea makeArea({
  List<MapTileSrc> layers = const [MapTileSrc.topo],
  bool isPolygon = false,
}) =>
    OfflineArea(
      id: "123",
      created: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      outline: [LatLng(37.5, -122.5), LatLng(37.5, -122.0), LatLng(37.0, -122.0), LatLng(37.0, -122.5)],
      isPolygon: isPolygon,
      layers: layers,
    );

void main() {
  group("OfflineArea json", () {
    test("round trip", () {
      final area = makeArea(layers: [MapTileSrc.topo, MapTileSrc.sectional], isPolygon: true)
        ..vfrVersion = "20240711"
        ..status = OfflineAreaStatus.complete
        ..completedJobs.add("topo@1-13")
        ..regionIds["topo"] = 7
        ..tileCount = 42
        ..bytes = 4200;

      final loaded = OfflineArea.fromJson(jsonDecode(jsonEncode(area.toJson())));
      expect(loaded.id, area.id);
      expect(loaded.created, area.created);
      expect(loaded.outline, area.outline);
      expect(loaded.isPolygon, true);
      expect(loaded.layers, [MapTileSrc.topo, MapTileSrc.sectional]);
      expect(loaded.vfrVersion, "20240711");
      expect(loaded.status, OfflineAreaStatus.complete);
      expect(loaded.completedJobs, {"topo@1-13"});
      expect(loaded.regionIds, {"topo": 7});
      expect(loaded.tileCount, 42);
      expect(loaded.bytes, 4200);
    });

    test("older areas without region ids load", () {
      final json = makeArea().toJson()..remove("regionIds");
      expect(OfflineArea.fromJson(json).regionIds, isEmpty);
    });

    test("unknown values are tolerated", () {
      final json = makeArea().toJson()
        ..["layers"] = ["topo", "airspace"]
        ..["status"] = "bogus";
      final loaded = OfflineArea.fromJson(json);
      expect(loaded.layers, [MapTileSrc.topo]);
      expect(loaded.status, OfflineAreaStatus.paused);
    });
  });

  group("planJobs", () {
    test("each layer gets its full zoom range", () {
      final jobs = makeArea(layers: MapTileSrc.values).planJobs().where((e) => e.src != null).toList();
      expect(jobs.length, MapTileSrc.values.length);
      for (final job in jobs) {
        expect(job.minZoom, offlineMinZoom);
        expect(job.maxZoom, offlineMaxZoom(job.src!));
      }
      expect(jobs.firstWhere((e) => e.src == MapTileSrc.topo).maxZoom, 13);
      expect(jobs.firstWhere((e) => e.src == MapTileSrc.sectional).maxZoom, 10);
      expect(jobs.firstWhere((e) => e.src == MapTileSrc.satellite).maxZoom, 14);
    });

    test("always includes elevation at z10 and z12", () {
      final dem = makeArea().planJobs().where((e) => e.src == null).toList();
      expect(dem.length, 2);
      expect(dem.map((e) => [e.minZoom, e.maxZoom]), [
        [10, 10],
        [12, 12]
      ]);
      expect(dem.every((e) => e.layerName == demLayerName), true);
    });

    test("MapTiler layers go through MapLibre, the rest tile by tile", () {
      final jobs = makeArea(layers: MapTileSrc.values).planJobs();
      for (final job in jobs) {
        final viaMapLibre = job.src == MapTileSrc.topo || job.src == MapTileSrc.satellite;
        expect(job.isMapLibreRegion, viaMapLibre, reason: job.key);
        expect(job.tileSource == null, viaMapLibre, reason: job.key);
      }
      expect(jobs.firstWhere((e) => e.src == MapTileSrc.sectional).tileSource!.name, "sectional");
      expect(jobs.firstWhere((e) => e.src == null).tileSource!.name, demLayerName);
    });

    test("job keys are unique", () {
      final area = makeArea(layers: MapTileSrc.values);
      final keys = area.planJobs().map((e) => e.key).toSet();
      expect(keys.length, area.planJobs().length);
    });
  });

  group("estimate", () {
    final topo = DownloadJob(src: MapTileSrc.topo, minZoom: 1, maxZoom: 10);
    final dem = DownloadJob(src: null, minZoom: 10, maxZoom: 10);

    test("size", () {
      final est = estimateDownload([(job: topo, tiles: 300), (job: dem, tiles: 100)], {"topo": 1000});
      expect(est.tiles, 400);
      expect(est.bytes,
          300 * 1000 + offlineRegionOverheadBytes["topo"]! + 100 * defaultAvgTileBytes[demLayerName]!);
      expect(est.isLarge, false);
      expect(est.isTooLarge, false);
    });

    test("thresholds", () {
      expect(estimateDownload([(job: dem, tiles: 10)], {}).isLarge, false);
      expect(estimateDownload([(job: topo, tiles: offlineWarnTiles + 1)], {"topo": 1}).isLarge, true);
      expect(estimateDownload([(job: topo, tiles: 10)], {"topo": offlineWarnBytes}).isLarge, true);
      final huge = estimateDownload([(job: topo, tiles: offlineMaxTiles + 1)], {});
      expect(huge.isTooLarge, true);
    });
  });

  group("tile count", () {
    final square = makeArea().outline;
    // Same box with a notch cut out of the east side
    final notched = [
      LatLng(37.5, -122.5),
      LatLng(37.5, -122.0),
      LatLng(37.4, -122.0),
      LatLng(37.25, -122.4),
      LatLng(37.1, -122.0),
      LatLng(37.0, -122.0),
      LatLng(37.0, -122.5),
    ];

    test("low zoom is a single tile", () {
      expect(countTilesAtZoom(square, false, 1), 1);
      expect(countTilesAtZoom(square, true, 1), 1);
      expect(countTilesAtZoom(square, true, 0), 1);
      expect(countTilesAtZoom([], true, 10), 0);
    });

    test("rectangle covers the corner tiles", () {
      for (final z in [5, 10, 14]) {
        final nw = tileXY(LatLng(37.5, -122.5), z);
        final se = tileXY(LatLng(37.0, -122.0), z);
        final expected = (se.$1.floor() - nw.$1.floor() + 1) * (se.$2.floor() - nw.$2.floor() + 1);
        expect(countTilesAtZoom(square, false, z), expected, reason: "z$z");
      }
    });

    test("enumerated tiles match the count", () {
      for (final outline in [square, notched]) {
        for (final z in [8, 12]) {
          final tiles = tilesAtZoom(outline, true, z).toList();
          expect(tiles.length, countTilesAtZoom(outline, true, z));
          expect(tiles.toSet().length, tiles.length, reason: "no duplicates");
        }
      }
    });

    test("polygon tiles are inside the bounding box", () {
      final box = tilesAtZoom(notched, false, 12).toSet();
      expect(box.containsAll(tilesAtZoom(notched, true, 12)), true);
    });

    test("polygon square equals rectangle", () {
      for (final z in [8, 12, 16]) {
        expect(countTilesAtZoom(square, true, z), countTilesAtZoom(square, false, z));
      }
    });

    test("notch removes tiles", () {
      final full = countTilesAtZoom(square, true, 14);
      final cut = countTilesAtZoom(notched, true, 14);
      expect(cut, lessThan(full));
      expect(cut, greaterThan(full * 0.6));
    });

    test("triangle is about half its bounding box", () {
      final tri = [LatLng(37.5, -122.5), LatLng(37.5, -122.0), LatLng(37.0, -122.5)];
      final ratio = countTilesAtZoom(tri, true, 16) / countTilesAtZoom(tri, false, 16);
      expect(ratio, closeTo(0.5, 0.02));
    });

    test("deep zoom is fast", () {
      final big = [LatLng(40, -125), LatLng(40, -115), LatLng(33, -115), LatLng(36, -120), LatLng(33, -125)];
      final watch = Stopwatch()..start();
      final count = countTilesAtZoom(big, true, 17);
      expect(count, greaterThan(1000000));
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });

    test("countJobs sums zoom ranges", () {
      final area = makeArea(layers: [MapTileSrc.topo, MapTileSrc.sectional], isPolygon: true);
      final counts = area.countJobs(area.planJobs());
      for (final each in counts) {
        // MapLibre regions are rectangles
        final polygon = !each.job.isMapLibreRegion;
        int expected = 0;
        for (int z = each.job.minZoom; z <= each.job.maxZoom; z++) {
          expected += countTilesAtZoom(area.outline, polygon, z);
        }
        expect(each.tiles, expected, reason: each.job.key);
      }
    });
  });

  test("sectional outdated", () {
    final area = makeArea(layers: [MapTileSrc.sectional])..vfrVersion = "20240711";
    expect(area.isSectionalOutdated("20240711"), false);
    expect(area.isSectionalOutdated("20240905"), true);
    expect(area.isSectionalOutdated(null), false);
    expect((makeArea()..vfrVersion = "20240711").isSectionalOutdated("20240905"), false);
  });
}
