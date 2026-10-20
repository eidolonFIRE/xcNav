import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'package:xcnav/dem_service.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/services/tile_cache.dart';

/// Name used for the elevation layer (it's not a [MapTileSrc])
const demLayerName = "dem";

/// Name used for the elevation tiles the map draws 3D terrain with (also not a [MapTileSrc])
const terrainLayerName = "terrain";

/// 3D terrain is downloaded down to this zoom. The map draws terrain from tiles a few zoom levels up anyway.
const offlineTerrainMaxZoom = 12;

/// Max tiles per second requested from each tile server we download from ourselves. Kept low so we don't get blocked.
const Map<String, int> offlineTilesPerSecond = {
  "sectional": 10,
  demLayerName: 20,
};

const offlineParallelThreads = 4;

/// Rough average size (bytes) of one tile position, for estimates.
/// Topo / satellite count everything the map engine stores for that tile: vector data, contours, etc.
const Map<String, int> defaultAvgTileBytes = {
  "topo": 160000,
  "sectional": 32000,
  "satellite": 150000,
  demLayerName: 85000,
  terrainLayerName: 50000,
};

/// What a map engine region downloads regardless of its size: its style (fonts, icons) and the low zoom tile packs.
/// (Small Bay Area areas, Oct 2026, came to about 65MB topo, 170MB satellite, and 65MB terrain in all.)
const Map<String, int> offlineRegionOverheadBytes = {
  "topo": 60 * 1024 * 1024,
  "satellite": 150 * 1024 * 1024,
  terrainLayerName: 60 * 1024 * 1024,
};

/// Low zoom levels are only a handful of tiles, so every layer is downloaded from here up to its max.
const offlineMinZoom = 1;

/// Deepest zoom downloaded for offline use.
///
/// Topo / satellite are map zoom levels (512px tiles). The sectional is a raster tile zoom (256px tiles),
/// so its 10 shows about as much detail as map zoom 9.
int offlineMaxZoom(MapTileSrc src) {
  switch (src) {
    case MapTileSrc.satellite:
      return 14;
    case MapTileSrc.sectional:
      return 10;
    case MapTileSrc.topo:
      return 13;
  }
}

const offlineWarnTiles = 50000;
const offlineWarnBytes = 500 * 1024 * 1024;
const offlineMaxTiles = 1000000;

enum OfflineAreaStatus { queued, downloading, paused, complete, failed }

class DownloadJob {
  /// null = elevation: [sampleDem]'s, or the map's 3D terrain when [isTerrain]
  final MapTileSrc? src;
  final bool isTerrain;
  final int minZoom;
  final int maxZoom;

  DownloadJob({required this.src, required this.minZoom, required this.maxZoom}) : isTerrain = false;

  /// Elevation tiles the map draws 3D terrain with
  DownloadJob.terrain({required this.minZoom, required this.maxZoom})
      : src = null,
        isTerrain = true;

  String get layerName => isTerrain ? terrainLayerName : src?.name ?? demLayerName;

  /// Unique within an area
  String get key => "$layerName@$minZoom-$maxZoom";

  /// Topo / satellite / 3D terrain go through the map engine's offline API (style, fonts, vector tiles and all).
  /// Everything else we download ourselves, tile by tile.
  bool get isMapEngineRegion => isTerrain || src == MapTileSrc.topo || src == MapTileSrc.satellite;

  int get tilesPerSecond => offlineTilesPerSecond[layerName] ?? 10;

  /// Source for tile by tile downloads
  RasterTileSource? get tileSource {
    if (isTerrain) return null;
    if (src == null) return demTileSource;
    if (src == MapTileSrc.sectional) return sectionalTiles;
    return null;
  }
}

class OfflineArea {
  final String id;
  final DateTime created;
  final List<LatLng> outline;
  final bool isPolygon;
  final List<MapTileSrc> layers;

  /// Sectional chart cycle that was downloaded
  String? vfrVersion;
  OfflineAreaStatus status;

  /// Keys of [DownloadJob]s that finished without network failures
  final Set<String> completedJobs;

  /// Actual stored size, updated after downloading
  int tileCount;
  int bytes;

  OfflineArea({
    required this.id,
    required this.created,
    required this.outline,
    required this.isPolygon,
    required this.layers,
    this.vfrVersion,
    this.status = OfflineAreaStatus.queued,
    Set<String>? completedJobs,
    this.tileCount = 0,
    this.bytes = 0,
  }) : completedJobs = completedJobs ?? {};

  LatLngBounds get bounds => LatLngBounds.fromPoints(outline);

  /// Tile count for each job. Each zoom level is only counted once, even when several layers share it.
  List<({DownloadJob job, int tiles})> countJobs(List<DownloadJob> jobs) {
    final Map<(int, bool), int> perZoom = {};
    int countZoom(int z, bool polygon) => perZoom[(z, polygon)] ??= countTilesAtZoom(outline, polygon, z);
    return jobs.map((job) {
      int tiles = 0;
      for (int z = job.minZoom; z <= job.maxZoom; z++) {
        tiles += countZoom(z, isPolygon);
      }
      return (job: job, tiles: tiles);
    }).toList();
  }

  bool isSectionalOutdated(String? currentVfrVersion) =>
      layers.contains(MapTileSrc.sectional) &&
      vfrVersion != null &&
      currentVfrVersion != null &&
      vfrVersion != currentVfrVersion;

  /// All the downloads needed for this area. Each layer gets every zoom level up to [offlineMaxZoom].
  /// Always included: elevation at the zoom levels [sampleDem] uses, and the map's 3D terrain.
  List<DownloadJob> planJobs() {
    final List<DownloadJob> jobs = [];
    for (final src in layers) {
      jobs.add(DownloadJob(src: src, minZoom: offlineMinZoom, maxZoom: offlineMaxZoom(src)));
    }
    jobs.add(DownloadJob.terrain(minZoom: offlineMinZoom, maxZoom: offlineTerrainMaxZoom));
    for (final z in demZoomLevels) {
      jobs.add(DownloadJob(src: null, minZoom: z, maxZoom: z));
    }
    return jobs;
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "created": created.millisecondsSinceEpoch,
        "outline": outline.map((e) => [e.latitude, e.longitude]).toList(),
        "isPolygon": isPolygon,
        "layers": layers.map((e) => e.name).toList(),
        "vfrVersion": vfrVersion,
        "status": status.name,
        "completedJobs": completedJobs.toList(),
        "tileCount": tileCount,
        "bytes": bytes,
      };

  factory OfflineArea.fromJson(Map<String, dynamic> json) => OfflineArea(
        id: json["id"],
        created: DateTime.fromMillisecondsSinceEpoch(json["created"]),
        outline:
            (json["outline"] as List).map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble())).toList(),
        isPolygon: json["isPolygon"] ?? false,
        layers: (json["layers"] as List)
            .map((e) => MapTileSrc.values.where((s) => s.name == e).firstOrNull)
            .nonNulls
            .toList(),
        vfrVersion: json["vfrVersion"],
        status: OfflineAreaStatus.values.where((s) => s.name == json["status"]).firstOrNull ?? OfflineAreaStatus.paused,
        completedJobs: ((json["completedJobs"] as List?) ?? []).cast<String>().toSet(),
        tileCount: json["tileCount"] ?? 0,
        bytes: json["bytes"] ?? 0,
      );
}

class DownloadEstimate {
  final int tiles;
  final int bytes;

  const DownloadEstimate({required this.tiles, required this.bytes});

  bool get isLarge => tiles > offlineWarnTiles || bytes > offlineWarnBytes;
  bool get isTooLarge => tiles > offlineMaxTiles;
}

/// Tiles at zoom [z] touched by the area, one merged span of columns per row: (row, firstX, lastX).
/// Rectangles use the bounding box of [outline].
///
/// Polygons are scanned one tile row at a time: a tile is counted if an edge passes through it, or if it lies
/// inside the polygon (even-odd rule). This works at tile resolution, so it stays fast at deep zoom levels.
Iterable<(int, int, int)> tileSpansAtZoom(List<LatLng> outline, bool isPolygon, int z) sync* {
  if (outline.isEmpty) return;
  final pts = outline.map((e) => tileXY(e, z)).toList();
  final minX = pts.map((e) => e.$1).reduce(min).floor();
  final maxX = pts.map((e) => e.$1).reduce(max).floor();
  final minY = pts.map((e) => e.$2).reduce(min).floor();
  final maxY = pts.map((e) => e.$2).reduce(max).floor();

  if (!isPolygon || pts.length < 3) {
    for (int row = minY; row <= maxY; row++) {
      yield (row, minX, maxX);
    }
    return;
  }

  for (int row = minY; row <= maxY; row++) {
    final top = row.toDouble();
    final bottom = top + 1;
    final mid = top + 0.5;
    final List<(int, int)> spans = [];
    final List<double> crossings = [];

    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final lo = min(a.$2, b.$2);
      final hi = max(a.$2, b.$2);

      // Tiles in this row the edge passes through
      if (hi >= top && lo < bottom) {
        if (a.$2 == b.$2) {
          spans.add((min(a.$1, b.$1).floor(), max(a.$1, b.$1).floor()));
        } else {
          double xAt(double y) => a.$1 + (b.$1 - a.$1) * (y - a.$2) / (b.$2 - a.$2);
          final x0 = xAt(max(lo, top));
          final x1 = xAt(min(hi, bottom));
          spans.add((min(x0, x1).floor(), max(x0, x1).floor()));
        }
      }

      // Interior crossings on the row's center line
      if ((a.$2 <= mid) != (b.$2 <= mid)) {
        crossings.add(a.$1 + (b.$1 - a.$1) * (mid - a.$2) / (b.$2 - a.$2));
      }
    }

    crossings.sort();
    for (int i = 0; i + 1 < crossings.length; i += 2) {
      spans.add((crossings[i].floor(), crossings[i + 1].floor()));
    }

    // Merge overlapping spans
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    int? curStart;
    int curEnd = 0;
    for (final s in spans) {
      if (curStart != null && s.$1 <= curEnd + 1) {
        curEnd = max(curEnd, s.$2);
      } else {
        if (curStart != null) yield (row, curStart, curEnd);
        curStart = s.$1;
        curEnd = s.$2;
      }
    }
    if (curStart != null) yield (row, curStart, curEnd);
  }
}

/// Number of tiles at zoom [z] touched by the area. See [tileSpansAtZoom].
int countTilesAtZoom(List<LatLng> outline, bool isPolygon, int z) =>
    tileSpansAtZoom(outline, isPolygon, z).fold(0, (sum, e) => sum + e.$3 - e.$2 + 1);

/// Every tile (x, y) at zoom [z] touched by the area
Iterable<(int, int)> tilesAtZoom(List<LatLng> outline, bool isPolygon, int z) sync* {
  for (final (row, x0, x1) in tileSpansAtZoom(outline, isPolygon, z)) {
    for (int x = x0; x <= x1; x++) {
      yield (x, row);
    }
  }
}

DownloadEstimate estimateDownload(Iterable<({DownloadJob job, int tiles})> counts, Map<String, int> avgTileBytes) {
  int tiles = 0;
  int bytes = 0;
  for (final each in counts) {
    tiles += each.tiles;
    bytes += each.tiles * (avgTileBytes[each.job.layerName] ?? defaultAvgTileBytes[each.job.layerName]!);
    if (each.job.isMapEngineRegion) bytes += offlineRegionOverheadBytes[each.job.layerName] ?? 0;
  }
  return DownloadEstimate(tiles: tiles, bytes: bytes);
}
