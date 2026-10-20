import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/datadog.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/offline_area.dart';
import 'package:xcnav/services/tile_cache.dart';

class OfflineProgress {
  final String areaId;
  final int tilesDone;
  final int tilesTotal;

  const OfflineProgress({required this.areaId, required this.tilesDone, required this.tilesTotal});

  double? get fraction => tilesTotal > 0 ? (tilesDone / tilesTotal).clamp(0, 1) : null;
}

/// Mapbox tile region id for [layer] of an area
String offlineRegionId(String areaId, String layer) => "${areaId}_$layer";

/// GeoJSON outline of [area], for Mapbox
Map<String?, Object?> offlineAreaGeometry(OfflineArea area) {
  final b = area.bounds;
  final ring = area.isPolygon ? area.outline : [b.northWest, b.northEast, b.southEast, b.southWest];
  return {
    "type": "Polygon",
    "coordinates": [
      [
        for (final p in [...ring, ring.first]) [p.longitude, p.latitude]
      ]
    ],
  };
}

/// What Mapbox downloads for a topo / satellite / terrain [job]
mb.TileRegionLoadOptions offlineRegionOptions(OfflineArea area, DownloadJob job) => mb.TileRegionLoadOptions(
      geometry: offlineAreaGeometry(area),
      descriptorsOptions: [
        mb.TilesetDescriptorOptions(
          // Terrain is just the elevation tiles. Map layers come with their style, fonts and icons (a style pack).
          styleURI: job.isTerrain ? "" : mapStyleUri(job.src!),
          minZoom: job.minZoom,
          maxZoom: job.maxZoom,
          tilesets: job.isTerrain ? [terrainTilesetUrl] : null,
          stylePackOptions: job.isTerrain
              ? null
              : mb.StylePackLoadOptions(
                  glyphsRasterizationMode: mb.GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
                  metadata: {"layer": job.layerName},
                  acceptExpired: false),
        ),
      ],
      metadata: {"areaId": area.id, "layer": job.layerName},
      acceptExpired: false,
      networkRestriction: mb.NetworkRestriction.NONE,
    );

/// Downloads map areas for offline use, one area and one layer at a time.
///
/// - Topo, satellite, and 3D terrain are Mapbox tile regions (with the style, fonts, and icons to draw them) in
///   Mapbox's tile store. The map uses them by itself when there's no network.
/// - Sectional and elevation tiles go in our own [tileCache], throttled per tile server.
class OfflineMapService with ChangeNotifier {
  /// Areas downloaded before the map engine change (flutter_map_tile_caching, "offlineMaps.areas") are left alone:
  /// their tiles are in a store this version can't read, and older versions still can.
  static const _prefsKey = "offlineMaps.v2.areas";

  final List<OfflineArea> areas = [];

  /// Non-null while a download is running
  final ValueNotifier<OfflineProgress?> progress = ValueNotifier(null);

  bool _running = false;
  String? _activeAreaId;
  bool _stopRequested = false;

  /// Mapbox tile region being downloaded
  String? _activeRegion;

  Future<mb.TileStore>? _tileStore;
  Future<mb.TileStore> get _store => _tileStore ??= mb.TileStore.createDefault();

  OfflineArea? byId(String id) => areas.where((e) => e.id == id).firstOrNull;

  bool isActive(String id) => _activeAreaId == id;

  Future init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        areas.clear();
        areas.addAll((jsonDecode(raw) as List).map((e) => OfflineArea.fromJson(e)));
      } catch (e, trace) {
        error("Offline maps: failed to load areas", errorMessage: e.toString(), errorStackTrace: trace);
      }
    }
    for (final area in areas) {
      // App was closed mid-download. Let the user resume it.
      if (area.status == OfflineAreaStatus.downloading || area.status == OfflineAreaStatus.queued) {
        area.status = OfflineAreaStatus.paused;
      }
      _registerTileStores(area);
    }
    notifyListeners();
    _cleanUp();
  }

  /// Mapbox tile regions and style packs no area needs, eg. left by an older version
  Future _cleanUp() async {
    try {
      final regions = {
        for (final area in areas)
          for (final job in area.planJobs().where((e) => e.isMapEngineRegion)) offlineRegionId(area.id, job.layerName)
      };
      final store = await _store;
      bool removed = false;
      for (final region in await store.allTileRegions()) {
        if (!regions.contains(region.id)) {
          await store.removeRegion(region.id);
          removed = true;
        }
      }
      final styles = {
        for (final area in areas)
          for (final layer in area.layers.where((e) => e != MapTileSrc.sectional)) mapStyleUri(layer)
      };
      final offline = await mb.OfflineManager.create();
      for (final pack in await offline.allStylePacks()) {
        if (!styles.contains(pack.styleURI)) {
          await offline.removeStylePack(pack.styleURI);
          removed = true;
        }
      }
      if (removed) await _reclaimSpace(store);
    } catch (e) {
      debugPrint("Offline maps: clean up failed: $e");
    }
  }

  /// Let the tile cache read this area's tiles while browsing
  void _registerTileStores(OfflineArea area) {
    for (final job in area.planJobs().where((e) => !e.isMapEngineRegion)) {
      tileCache.offlineAreas.putIfAbsent(job.layerName, () => {}).add(area.id);
    }
  }

  Future _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(areas.map((e) => e.toJson()).toList()));
  }

  void _changed() {
    _save();
    notifyListeners();
  }

  /// Off the UI thread, since huge areas at deep zoom can still take a moment.
  Future<List<({DownloadJob job, int tiles})>> _countJobs(OfflineArea area, List<DownloadJob> jobs) =>
      compute((args) => args.area.countJobs(args.jobs), (area: area, jobs: jobs));

  Future<DownloadEstimate> estimate(OfflineArea area) async {
    final counts = await _countJobs(area, area.planJobs());
    int tiles = 0;
    int bytes = 0;
    for (final each in counts) {
      tiles += each.tiles;
      // Mapbox downloads tiles in packs, much coarser than tile by tile. Ask it.
      final mapbox = each.job.isMapEngineRegion ? await _estimateRegion(area, each.job) : null;
      bytes += mapbox ?? estimateDownload([each], defaultAvgTileBytes).bytes;
    }
    return DownloadEstimate(tiles: tiles, bytes: bytes);
  }

  /// Mapbox's estimate of the space [job] takes. Null when it can't tell (eg. no network), or only guesses.
  Future<int?> _estimateRegion(OfflineArea area, DownloadJob job) async {
    try {
      final store = await _store;
      final result = await store.estimateTileRegion(
          "estimate_${job.layerName}",
          offlineRegionOptions(area, job),
          mb.TileRegionEstimateOptions(errorMargin: 0.1, preciseEstimationTimeout: 5, timeout: 20),
          null);
      debugPrint("Offline maps: estimate ${job.layerName} ${result.storageSize} bytes, margin ${result.errorMargin}");
      // Big areas only get a rough guess: an infinite or NaN margin, sometimes 0 bytes. Ours is as good then.
      if (!result.errorMargin.isFinite || result.storageSize <= 0) return null;
      return result.storageSize;
    } catch (e) {
      debugPrint("Offline maps: no estimate for ${job.layerName}: $e");
      return null;
    }
  }

  void enqueue(OfflineArea area) {
    area.status = OfflineAreaStatus.queued;
    area.vfrVersion ??= vfrVersion;
    areas.add(area);
    _registerTileStores(area);
    _changed();
    _run();
  }

  /// Stop [area]'s download, if it's the one running
  Future _stopActive(OfflineArea area) async {
    if (!isActive(area.id)) return;
    _stopRequested = true;
    final region = _activeRegion;
    if (region != null) {
      // Mapbox has no cancel. Loading the region again cancels the load in progress, and this one stops right away
      // since it may not use the network.
      _store
          .then((store) => store.loadTileRegion(
              region,
              mb.TileRegionLoadOptions(acceptExpired: true, networkRestriction: mb.NetworkRestriction.DISALLOW_ALL),
              null))
          // Ends in an error when there's more to download, as expected
          .then<void>((_) {}, onError: (_) => debugPrint("Offline maps: paused $region"));
    }
  }

  Future pause(String id) async {
    final area = byId(id);
    if (area == null) return;
    area.status = OfflineAreaStatus.paused;
    _changed();
    await _stopActive(area);
  }

  void resume(String id) {
    final area = byId(id);
    if (area == null) return;
    area.status = OfflineAreaStatus.queued;
    _changed();
    _run();
  }

  /// Sectional tiles are tied to the chart cycle. Drop the old ones and fetch the current cycle.
  Future updateSectional(String id) async {
    final area = byId(id);
    if (area == null || isActive(id)) return;
    await tileCache.deleteAreaSource(area.id, MapTileSrc.sectional.name);
    tileCache.offlineAreas.putIfAbsent(MapTileSrc.sectional.name, () => {}).add(area.id);
    area.completedJobs.removeWhere((key) => key.startsWith("${MapTileSrc.sectional.name}@"));
    area.vfrVersion = vfrVersion;
    resume(id);
  }

  Future delete(String id) async {
    final area = byId(id);
    if (area == null) return;
    areas.remove(area);
    _changed();
    await _stopActive(area);
    await _deleteRegions(area);
    try {
      await tileCache.deleteArea(area.id);
    } catch (e, trace) {
      error("Offline maps: failed to delete tiles", errorMessage: e.toString(), errorStackTrace: trace);
    }
  }

  /// [area]'s Mapbox tile regions, and the style packs no other area needs
  Future _deleteRegions(OfflineArea area) async {
    final jobs = area.planJobs().where((e) => e.isMapEngineRegion);
    if (jobs.isEmpty) return;
    try {
      final store = await _store;
      for (final job in jobs) {
        try {
          await store.removeRegion(offlineRegionId(area.id, job.layerName));
        } catch (e) {
          // Never got as far as downloading
          debugPrint("Offline maps: couldn't remove region ${job.layerName}: $e");
        }
      }
      final unused = area.layers.where((layer) =>
          (layer == MapTileSrc.topo || layer == MapTileSrc.satellite) && !areas.any((e) => e.layers.contains(layer)));
      if (unused.isNotEmpty) {
        final offline = await mb.OfflineManager.create();
        for (final layer in unused) {
          await offline.removeStylePack(mapStyleUri(layer)).then<void>((_) {}, onError: (e) => debugPrint("$e"));
        }
      }
      await _reclaimSpace(store);
    } catch (e, trace) {
      error("Offline maps: failed to delete regions", errorMessage: e.toString(), errorStackTrace: trace);
    }
  }

  /// Mapbox frees the space of removed regions only once it needs it. Make it do so now.
  /// (The disk quota doesn't touch tiles that regions still use.)
  Future _reclaimSpace(mb.TileStore store) async {
    await store.setDiskQuota(0);
    await store.setDiskQuota(null);
  }

  Future _run() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final area = areas.where((e) => e.status == OfflineAreaStatus.queued).firstOrNull;
        if (area == null) break;
        await _downloadArea(area);
      }
    } finally {
      _running = false;
      _activeAreaId = null;
      progress.value = null;
      notifyListeners();
    }
  }

  Future _downloadArea(OfflineArea area) async {
    _activeAreaId = area.id;
    _stopRequested = false;
    area.status = OfflineAreaStatus.downloading;
    _changed();

    try {
      final counts = await _countJobs(area, area.planJobs().where((e) => !area.completedJobs.contains(e.key)).toList());
      final total = counts.fold(0, (sum, e) => sum + e.tiles);
      int done = 0;

      for (final each in counts) {
        if (_stopRequested) break;
        final job = each.job;
        debugPrint("Offline maps: downloading ${area.id} ${job.key} (${each.tiles} tiles)");

        void report(int jobDone) =>
            progress.value = OfflineProgress(areaId: area.id, tilesDone: done + jobDone, tilesTotal: total);

        final complete = job.isMapEngineRegion
            ? await _downloadRegion(area, job, (fraction) => report((fraction * each.tiles).round()))
            : await _downloadTiles(area, job, report);
        if (_stopRequested) break;

        done += each.tiles;
        // 404s etc. won't fix themselves (eg. outside sectional coverage). Only network failures need a retry.
        if (complete) {
          area.completedJobs.add(job.key);
          await _save();
        }
      }
    } catch (e, trace) {
      error("Offline maps: download failed", errorMessage: e.toString(), errorStackTrace: trace);
      if (area.status == OfflineAreaStatus.downloading) area.status = OfflineAreaStatus.failed;
    }

    // Deleted while downloading
    if (!areas.contains(area)) return;

    if (area.status == OfflineAreaStatus.downloading) {
      final allDone = area.planJobs().every((e) => area.completedJobs.contains(e.key));
      area.status = allDone ? OfflineAreaStatus.complete : OfflineAreaStatus.failed;
    }
    await _updateStats(area);
    _changed();
  }

  /// Our own tiles (sectional, elevation). Returns false if any tile failed for a reason worth retrying.
  Future<bool> _downloadTiles(OfflineArea area, DownloadJob job, void Function(int done) report) async {
    final src = job.tileSource!;
    tileCache.offlineAreas.putIfAbsent(src.name, () => {}).add(area.id);
    final tiles = <(int, int, int)>[
      for (int z = job.minZoom; z <= job.maxZoom; z++)
        for (final (x, y) in tilesAtZoom(area.outline, area.isPolygon, z)) (z, x, y)
    ];

    int next = 0;
    int attempted = 0;
    int failures = 0;
    // Each worker takes the next tile, spacing requests out to stay under the rate limit overall.
    final interval = Duration(microseconds: (1000000 * offlineParallelThreads / job.tilesPerSecond).round());
    Future worker() async {
      while (!_stopRequested && next < tiles.length) {
        final (z, x, y) = tiles[next++];
        final started = DateTime.now();
        try {
          await tileCache.downloadTile(area.id, src, z, x, y);
        } on TileFetchException {
          failures++;
        }
        attempted++;
        if (attempted % 10 == 0 || attempted == tiles.length) report(attempted);
        final wait = interval - DateTime.now().difference(started);
        if (wait > Duration.zero) await Future.delayed(wait);
      }
    }

    await Future.wait(List.generate(offlineParallelThreads, (_) => worker()));
    return failures == 0 && !_stopRequested;
  }

  /// Topo / satellite / terrain as a Mapbox tile region. Resolves when it finishes (true when it's all there), fails,
  /// or is paused. Loading the region again picks up where it left off, after a restart too.
  Future<bool> _downloadRegion(OfflineArea area, DownloadJob job, void Function(double fraction) report) async {
    final id = offlineRegionId(area.id, job.layerName);
    _activeRegion = id;
    try {
      final store = await _store;
      final region = await store.loadTileRegion(id, offlineRegionOptions(area, job), (progress) {
        if (progress.requiredResourceCount > 0) {
          report(progress.completedResourceCount / progress.requiredResourceCount);
        }
      });
      debugPrint("Offline maps: region $id ${region.completedResourceCount}/${region.requiredResourceCount}, "
          "${region.completedResourceSize} bytes");
      // Nothing to load means Mapbox couldn't resolve the layer (eg. MapTiler's styles): not done
      return region.requiredResourceCount > 0 && region.completedResourceCount >= region.requiredResourceCount;
    } catch (e) {
      // Pausing cancels the load
      if (!_stopRequested) debugPrint("Offline maps: region $id failed: $e");
      return false;
    } finally {
      _activeRegion = null;
    }
  }

  Future _updateStats(OfflineArea area) async {
    final stats = await tileCache.areaStats(area.id);
    int tiles = stats.files;
    int bytes = stats.bytes;
    for (final job in area.planJobs().where((e) => e.isMapEngineRegion)) {
      try {
        final region = await (await _store).tileRegion(offlineRegionId(area.id, job.layerName));
        tiles += region.completedResourceCount;
        bytes += region.completedResourceSize;
      } catch (e) {
        debugPrint("Offline maps: couldn't read stats for ${job.layerName}: $e");
      }
    }
    area.tileCount = tiles;
    area.bytes = bytes;
  }
}

final offlineMapService = OfflineMapService();
