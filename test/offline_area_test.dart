import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/map_service.dart';
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
        ..completedJobs.add("topo@1-16")
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
      expect(loaded.completedJobs, {"topo@1-16"});
      expect(loaded.tileCount, 42);
      expect(loaded.bytes, 4200);
    });

    test("region type", () {
      expect(makeArea().toRegion(), isA<RectangleRegion>());
      expect(makeArea(isPolygon: true).toRegion(), isA<CustomPolygonRegion>());
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
      expect(jobs.firstWhere((e) => e.src == MapTileSrc.topo).maxZoom, 14);
      expect(jobs.firstWhere((e) => e.src == MapTileSrc.sectional).maxZoom, 10);
      expect(jobs.firstWhere((e) => e.src == MapTileSrc.satellite).maxZoom, 15);
    });

    test("always includes elevation at z9 to z12", () {
      final dem = makeArea().planJobs().where((e) => e.src == null).toList();
      expect(dem.length, 4);
      expect(dem.map((e) => [e.minZoom, e.maxZoom]), [
        [9, 9],
        [10, 10],
        [11, 11],
        [12, 12]
      ]);
      expect(dem.every((e) => e.layerName == demLayerName), true);
    });

    test("store names are per area and layer", () {
      final area = makeArea(layers: [MapTileSrc.topo, MapTileSrc.satellite]);
      expect(area.storeNames, ["offline_123_topo", "offline_123_satellite", "offline_123_dem"]);
      final keys = area.planJobs().map((e) => e.key).toSet();
      expect(keys.length, area.planJobs().length);
    });
  });

  group("estimate", () {
    final topo = DownloadJob(src: MapTileSrc.topo, minZoom: 1, maxZoom: 10, storeName: "a");
    final dem = DownloadJob(src: null, minZoom: 10, maxZoom: 10, storeName: "b");

    test("size", () {
      final est = estimateDownload([(job: topo, tiles: 300), (job: dem, tiles: 100)], {"topo": 1000});
      expect(est.tiles, 400);
      expect(est.bytes, 300 * 1000 + 100 * defaultAvgTileBytes[demLayerName]!);
      expect(est.isLarge, false);
      expect(est.isTooLarge, false);
    });

    test("thresholds", () {
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

    Future<int> fmtcCount(BaseRegion region, int z) => FMTCStore("test").download.countTiles(
        region.toDownloadable(minZoom: z, maxZoom: z, options: TileLayer(urlTemplate: "x/{z}/{x}/{y}")));

    test("low zoom is a single tile", () {
      expect(countTilesAtZoom(square, false, 1), 1);
      expect(countTilesAtZoom(square, true, 1), 1);
      expect(countTilesAtZoom(square, true, 0), 1);
      expect(countTilesAtZoom([], true, 10), 0);
    });

    test("rectangle matches FMTC", () async {
      for (final z in [5, 10, 14]) {
        final region = RectangleRegion(LatLngBounds.fromPoints(square));
        expect(countTilesAtZoom(square, false, z), await fmtcCount(region, z), reason: "z$z");
      }
    });

    test("polygon close to FMTC", () async {
      for (final outline in [square, notched]) {
        for (final z in [8, 12, 14]) {
          final mine = countTilesAtZoom(outline, true, z);
          final theirs = await fmtcCount(CustomPolygonRegion(outline), z);
          expect((mine - theirs).abs() / theirs, lessThan(0.05), reason: "z$z mine=$mine fmtc=$theirs");
        }
      }
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
        int expected = 0;
        for (int z = each.job.minZoom; z <= each.job.maxZoom; z++) {
          expected += countTilesAtZoom(area.outline, true, z);
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
