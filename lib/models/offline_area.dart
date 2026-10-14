import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/dem_service.dart';
import 'package:xcnav/map_service.dart';

/// Prefix for FMTC stores holding offline map downloads. These are never purged by the browse cache.
const offlineStorePrefix = "offline_";

/// Name used for the elevation layer (it's not a [MapTileSrc])
const demLayerName = "dem";

/// Max tiles per second requested from each tile server. Kept low so we don't get blocked.
const Map<String, int> offlineTilesPerSecond = {
  "topo": 6,
  "sectional": 10,
  "satellite": 16,
  demLayerName: 20,
};

const offlineParallelThreads = 4;

/// Fallback average tile size (bytes) when the browse cache doesn't have enough tiles to measure.
/// Measured from a browse cache sample (topo 130, sectional 91, satellite 198, dem 11 tiles).
const Map<String, int> defaultAvgTileBytes = {
  "topo": 40000,
  "sectional": 32000,
  "satellite": 17500,
  demLayerName: 85000,
};

/// Low zoom levels are only a handful of tiles, so every layer is downloaded from here up to its native max.
const offlineMinZoom = 1;

/// Deepest zoom downloaded for offline use. Some layers stop short of their native max because the deepest
/// levels explode the download size for little benefit.
int offlineMaxZoom(MapTileSrc src) {
  final native = mapTileMaxNativeZoom(src);
  switch (src) {
    case MapTileSrc.satellite:
      return native > 17 ? 17 : native;
    case MapTileSrc.sectional:
      return native > 10 ? 10 : native;
    case MapTileSrc.topo:
      return native;
  }
}

const offlineWarnTiles = 50000;
const offlineWarnBytes = 500 * 1024 * 1024;
const offlineMaxTiles = 1000000;

enum OfflineAreaStatus { queued, downloading, paused, complete, failed }

class DownloadJob {
  /// null = elevation (DEM)
  final MapTileSrc? src;
  final int minZoom;
  final int maxZoom;
  final String storeName;

  DownloadJob({required this.src, required this.minZoom, required this.maxZoom, required this.storeName});

  String get layerName => src?.name ?? demLayerName;

  /// Unique within an area
  String get key => "$layerName@$minZoom-$maxZoom";

  int get tilesPerSecond => offlineTilesPerSecond[layerName]!;

  TileLayer get tileLayer => src != null ? mapTileDownloadLayer(src!) : demDownloadLayer();

  DownloadableRegion toDownloadable(BaseRegion region) =>
      region.toDownloadable(minZoom: minZoom, maxZoom: maxZoom, options: tileLayer);
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

  BaseRegion toRegion() => isPolygon ? CustomPolygonRegion(outline) : RectangleRegion(LatLngBounds.fromPoints(outline));

  String storeName(String layerName) => "$offlineStorePrefix${id}_$layerName";

  /// Tile count for each job. Each zoom level is only counted once, even when several layers share it.
  List<({DownloadJob job, int tiles})> countJobs(List<DownloadJob> jobs) {
    final Map<int, int> perZoom = {};
    int countZoom(int z) => perZoom[z] ??= countTilesAtZoom(outline, isPolygon, z);
    return jobs.map((job) {
      int tiles = 0;
      for (int z = job.minZoom; z <= job.maxZoom; z++) {
        tiles += countZoom(z);
      }
      return (job: job, tiles: tiles);
    }).toList();
  }

  List<String> get storeNames => [...layers.map((e) => storeName(e.name)), storeName(demLayerName)];

  bool isSectionalOutdated(String? currentVfrVersion) =>
      layers.contains(MapTileSrc.sectional) &&
      vfrVersion != null &&
      currentVfrVersion != null &&
      vfrVersion != currentVfrVersion;

  /// All the downloads needed for this area. Each layer gets every zoom level up to [offlineMaxZoom].
  /// Elevation is always included at the zoom levels [sampleDem] uses.
  List<DownloadJob> planJobs() {
    final List<DownloadJob> jobs = [];
    for (final src in layers) {
      jobs.add(
          DownloadJob(src: src, minZoom: offlineMinZoom, maxZoom: offlineMaxZoom(src), storeName: storeName(src.name)));
    }
    for (final z in demZoomLevels) {
      jobs.add(DownloadJob(src: null, minZoom: z, maxZoom: z, storeName: storeName(demLayerName)));
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

/// Fractional slippy-map tile coordinate (web mercator) of a point at zoom [z].
(double, double) _tileXY(LatLng p, int z) {
  final n = (1 << z).toDouble();
  final lat = p.latitude.clamp(-85.05112878, 85.05112878) * pi / 180;
  final x = (p.longitude + 180) / 360 * n;
  final y = (1 - log(tan(lat) + 1 / cos(lat)) / pi) / 2 * n;
  return (x.clamp(0, n - 1e-9), y.clamp(0, n - 1e-9));
}

/// Number of tiles at zoom [z] touched by the area. Rectangles use the bounding box of [outline].
///
/// Polygons are scanned one tile row at a time: a tile is counted if an edge passes through it, or if it lies
/// inside the polygon (even-odd rule). This works at tile resolution, so it stays fast at deep zoom levels.
int countTilesAtZoom(List<LatLng> outline, bool isPolygon, int z) {
  if (outline.isEmpty) return 0;
  final pts = outline.map((e) => _tileXY(e, z)).toList();
  final minX = pts.map((e) => e.$1).reduce(min).floor();
  final maxX = pts.map((e) => e.$1).reduce(max).floor();
  final minY = pts.map((e) => e.$2).reduce(min).floor();
  final maxY = pts.map((e) => e.$2).reduce(max).floor();

  if (!isPolygon || pts.length < 3) {
    return (maxX - minX + 1) * (maxY - minY + 1);
  }

  int total = 0;
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

    // Merge overlapping spans and count tiles
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    int? curStart;
    int curEnd = 0;
    for (final s in spans) {
      if (curStart != null && s.$1 <= curEnd + 1) {
        curEnd = max(curEnd, s.$2);
      } else {
        if (curStart != null) total += curEnd - curStart + 1;
        curStart = s.$1;
        curEnd = s.$2;
      }
    }
    if (curStart != null) total += curEnd - curStart + 1;
  }
  return total;
}

DownloadEstimate estimateDownload(Iterable<({DownloadJob job, int tiles})> counts, Map<String, int> avgTileBytes) {
  int tiles = 0;
  int bytes = 0;
  for (final each in counts) {
    tiles += each.tiles;
    bytes += each.tiles * (avgTileBytes[each.job.layerName] ?? defaultAvgTileBytes[each.job.layerName]!);
  }
  return DownloadEstimate(tiles: tiles, bytes: bytes);
}
