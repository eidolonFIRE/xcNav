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

DownloadEstimate estimateDownload(Iterable<({DownloadJob job, int tiles})> counts, Map<String, int> avgTileBytes) {
  int tiles = 0;
  int bytes = 0;
  for (final each in counts) {
    tiles += each.tiles;
    bytes += each.tiles * (avgTileBytes[each.job.layerName] ?? defaultAvgTileBytes[each.job.layerName]!);
  }
  return DownloadEstimate(tiles: tiles, bytes: bytes);
}
