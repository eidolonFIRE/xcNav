import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
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

/// A MapLibre offline region download we're following
class _RegionDownload {
  int? regionId;
  Completer<bool> done = Completer();
  void Function(double fraction)? onProgress;

  void finish(bool success) {
    if (!done.isCompleted) done.complete(success);
  }
}

/// Downloads map areas for offline use, one area and one layer at a time.
///
/// - MapTiler layers (topo, satellite) are MapLibre offline regions: MapLibre fetches the style, fonts, and tiles.
/// - Sectional and elevation tiles go in our own [tileCache], throttled per tile server.
class OfflineMapService with ChangeNotifier {
  /// Areas downloaded before MapLibre (flutter_map_tile_caching, "offlineMaps.areas") are left alone:
  /// their tiles are in a store this version can't read, and older versions still can.
  static const _prefsKey = "offlineMaps.v2.areas";

  final List<OfflineArea> areas = [];

  /// Non-null while a download is running
  final ValueNotifier<OfflineProgress?> progress = ValueNotifier(null);

  bool _running = false;
  String? _activeAreaId;
  bool _stopRequested = false;

  /// MapLibre downloads started this session, by `areaId/layer`. Only these can be paused and resumed;
  /// after a restart MapLibre makes us start a region over.
  final Map<String, _RegionDownload> _regionDownloads = {};
  _RegionDownload? _activeRegion;

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
  }

  /// Let the tile cache read this area's tiles while browsing
  void _registerTileStores(OfflineArea area) {
    for (final job in area.planJobs().where((e) => !e.isMapLibreRegion)) {
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
    return estimateDownload(await _countJobs(area, area.planJobs()), defaultAvgTileBytes);
  }

  void enqueue(OfflineArea area) {
    area.status = OfflineAreaStatus.queued;
    area.vfrVersion ??= vfrVersion;
    areas.add(area);
    _registerTileStores(area);
    _changed();
    _run();
  }

  Future _stopActive(OfflineArea area) async {
    if (!isActive(area.id)) return;
    _stopRequested = true;
    final region = _activeRegion;
    if (region?.regionId != null) {
      try {
        await ml.pauseOfflineRegionDownload(region!.regionId!);
      } catch (e) {
        debugPrint("Offline maps: pause failed: $e");
      }
    }
    region?.finish(false);
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
    for (final regionId in area.regionIds.values) {
      try {
        await ml.deleteOfflineRegion(regionId);
      } catch (e) {
        debugPrint("Offline maps: couldn't delete region $regionId: $e");
      }
    }
    _regionDownloads.removeWhere((key, _) => key.startsWith("${area.id}/"));
    try {
      await tileCache.deleteArea(area.id);
    } catch (e, trace) {
      error("Offline maps: failed to delete tiles", errorMessage: e.toString(), errorStackTrace: trace);
    }
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

        final complete = job.isMapLibreRegion
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
    _activeRegion = null;

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

  /// MapTiler layer as a MapLibre offline region. Resolves when it finishes (true), fails, or is paused.
  Future<bool> _downloadRegion(OfflineArea area, DownloadJob job, void Function(double fraction) report) async {
    final key = "${area.id}/${job.layerName}";
    final existing = _regionDownloads[key];
    final region = existing ?? _RegionDownload();
    region.done = Completer();
    region.onProgress = report;
    _activeRegion = region;

    if (existing?.regionId != null) {
      // Paused earlier this session: pick up where it left off
      try {
        await ml.resumeOfflineRegionDownload(existing!.regionId!);
        return await region.done.future;
      } catch (e) {
        debugPrint("Offline maps: resume failed, starting over: $e");
      }
    }

    _regionDownloads[key] = region;
    final bounds = area.bounds;
    final created = await ml.downloadOfflineRegion(
      ml.OfflineRegionDefinition(
        bounds: ml.LatLngBounds(
            southwest: ml.LatLng(bounds.south, bounds.west), northeast: ml.LatLng(bounds.north, bounds.east)),
        mapStyleUrl: maptilerStyleUrl(job.src!)!,
        minZoom: job.minZoom.toDouble(),
        maxZoom: job.maxZoom.toDouble(),
      ),
      metadata: {"areaId": area.id, "layer": job.layerName},
      onEvent: (status) {
        if (status is ml.InProgress) {
          region.onProgress?.call(status.progress / 100);
        } else if (status is ml.Success) {
          region.finish(true);
        } else if (status is ml.Error) {
          debugPrint("Offline maps: region $key failed: ${status.cause}");
          region.finish(false);
        }
      },
    );
    region.regionId = created.id;
    area.regionIds[job.layerName] = created.id;
    await _save();
    if (_stopRequested) {
      // Paused while MapLibre was still setting up the region
      await ml.pauseOfflineRegionDownload(created.id);
      region.finish(false);
    }
    return region.done.future;
  }

  Future _updateStats(OfflineArea area) async {
    final stats = await tileCache.areaStats(area.id);
    int tiles = stats.files;
    int bytes = stats.bytes;
    for (final regionId in area.regionIds.values) {
      try {
        final status = await ml.getOfflineRegionStatus(regionId);
        tiles += status.completedResourceCount;
        bytes += status.completedResourceSize;
      } catch (e) {
        debugPrint("Offline maps: couldn't read stats for region $regionId: $e");
      }
    }
    area.tileCount = tiles;
    area.bytes = bytes;
  }
}

final offlineMapService = OfflineMapService();
