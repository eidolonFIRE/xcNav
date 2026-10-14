import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/datadog.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/offline_area.dart';

class OfflineProgress {
  final String areaId;
  final int tilesDone;
  final int tilesTotal;

  const OfflineProgress({required this.areaId, required this.tilesDone, required this.tilesTotal});

  double? get fraction => tilesTotal > 0 ? (tilesDone / tilesTotal).clamp(0, 1) : null;
}

/// Downloads map areas for offline use, one area and one layer at a time, throttled per tile server.
class OfflineMapService with ChangeNotifier {
  static const _prefsKey = "offlineMaps.areas";

  final List<OfflineArea> areas = [];

  /// Non-null while a download is running
  final ValueNotifier<OfflineProgress?> progress = ValueNotifier(null);

  bool _running = false;
  String? _activeAreaId;
  bool _stopRequested = false;

  /// Measured once per session; it's only a rough figure for the estimate.
  Map<String, int>? _avgTileBytesCache;

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
    // App was closed mid-download. Let the user resume it.
    for (final area in areas) {
      if (area.status == OfflineAreaStatus.downloading || area.status == OfflineAreaStatus.queued) {
        area.status = OfflineAreaStatus.paused;
      }
    }
    notifyListeners();
  }

  Future _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(areas.map((e) => e.toJson()).toList()));
  }

  void _changed() {
    _save();
    notifyListeners();
  }

  /// Re-measure average tile sizes on the next estimate (browse cache may have grown).
  void resetAvgTileBytes() => _avgTileBytesCache = null;

  /// Average tile size per layer, measured from the browse cache when it has enough samples.
  Future<Map<String, int>> _avgTileBytes() async {
    if (_avgTileBytesCache != null) return _avgTileBytesCache!;
    final Map<String, int> retval = Map.of(defaultAvgTileBytes);
    for (final name in retval.keys.toList()) {
      try {
        final store = FMTCStore(name);
        if (!await store.manage.ready) continue;
        final stats = await store.stats.all;
        if (stats.length >= 200) {
          retval[name] = (stats.size * 1024 / stats.length).round();
        }
      } catch (e) {
        debugPrint("Offline maps: couldn't measure $name tile size: $e");
      }
    }
    return _avgTileBytesCache = retval;
  }

  /// Off the UI thread, since huge areas at deep zoom can still take a moment.
  Future<List<({DownloadJob job, int tiles})>> _countJobs(OfflineArea area, List<DownloadJob> jobs) =>
      compute((args) => args.area.countJobs(args.jobs), (area: area, jobs: jobs));

  Future<DownloadEstimate> estimate(OfflineArea area) async {
    return estimateDownload(await _countJobs(area, area.planJobs()), await _avgTileBytes());
  }

  void enqueue(OfflineArea area) {
    area.status = OfflineAreaStatus.queued;
    area.vfrVersion ??= vfrVersion;
    areas.add(area);
    _changed();
    _run();
  }

  Future pause(String id) async {
    final area = byId(id);
    if (area == null) return;
    area.status = OfflineAreaStatus.paused;
    _changed();
    if (isActive(id)) {
      _stopRequested = true;
      await FMTCStore(area.storeName(demLayerName)).download.cancel();
    }
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
    final store = FMTCStore(area.storeName(MapTileSrc.sectional.name));
    if (await store.manage.ready) await store.manage.delete();
    area.completedJobs.removeWhere((key) => key.startsWith("${MapTileSrc.sectional.name}@"));
    area.vfrVersion = vfrVersion;
    resume(id);
  }

  Future delete(String id) async {
    final area = byId(id);
    if (area == null) return;
    areas.remove(area);
    _changed();
    if (isActive(id)) {
      _stopRequested = true;
      await FMTCStore(area.storeName(demLayerName)).download.cancel();
    }
    for (final name in area.storeNames) {
      try {
        final store = FMTCStore(name);
        if (await store.manage.ready) await store.manage.delete();
      } catch (e, trace) {
        error("Offline maps: failed to delete store",
            errorMessage: e.toString(), errorStackTrace: trace, attributes: {"store": name});
      }
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
      final region = area.toRegion();
      final counts = await _countJobs(area, area.planJobs().where((e) => !area.completedJobs.contains(e.key)).toList());
      final total = counts.fold(0, (sum, e) => sum + e.tiles);
      int done = 0;

      for (final each in counts) {
        if (_stopRequested) break;
        final job = each.job;
        final store = FMTCStore(job.storeName);
        await store.manage.create();

        debugPrint("Offline maps: downloading ${area.id} ${job.key} (${each.tiles} tiles)");
        final streams = store.download.startForeground(
          region: job.toDownloadable(region),
          parallelThreads: offlineParallelThreads,
          rateLimit: job.tilesPerSecond,
          skipExistingTiles: true,
          skipSeaTiles: false,
          disableRecovery: true,
        );

        DownloadProgress? last;
        await for (final p in streams.downloadProgress) {
          last = p;
          progress.value = OfflineProgress(areaId: area.id, tilesDone: done + p.attemptedTilesCount, tilesTotal: total);
        }
        if (_stopRequested) break;

        done += each.tiles;
        // 404s etc. won't fix themselves (eg. outside sectional coverage). Only network failures need a retry.
        if ((last?.failedRequestTilesCount ?? 0) == 0) {
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

  Future _updateStats(OfflineArea area) async {
    int tiles = 0;
    double kib = 0;
    for (final name in area.storeNames) {
      try {
        final store = FMTCStore(name);
        if (!await store.manage.ready) continue;
        final stats = await store.stats.all;
        tiles += stats.length;
        kib += stats.size;
      } catch (e) {
        debugPrint("Offline maps: couldn't read stats for $name: $e");
      }
    }
    area.tileCount = tiles;
    area.bytes = (kib * 1024).round();
  }
}

final offlineMapService = OfflineMapService();
