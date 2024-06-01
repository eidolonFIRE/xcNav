import 'dart:math';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:path_provider/path_provider.dart';

import 'package:xcnav/datadog.dart';
import 'package:xcnav/dem_service.dart';

enum MapTileSrc {
  topo,
  sectional,
  satellite,
  // airspace,
  // airports,
}

bool mapServiceIsInit = false;

TileProvider? _makeTileProvider(String instanceName) {
  debugPrint("------ make tile provider \"$instanceName\" ----");
  if (!mapServiceIsInit) return null;
  try {
    return FMTCStore(instanceName).getTileProvider();
  } catch (e, trace) {
    error("FMTC: Error making tile provider",
        errorMessage: e.toString(), errorStackTrace: trace, attributes: {"layerName": instanceName});
    return null;
  }
}

Map<MapTileSrc, TileLayer> _tileLayersCache = {};

TileLayer _buildMapTileLayer(MapTileSrc tileSrc) {
  final tileName = tileSrc.toString().split(".").last;
  switch (tileSrc) {
    case MapTileSrc.sectional:
      return TileLayer(
        urlTemplate: 'https://vfrmap.com/20231130/tiles/vfrc/{z}/{y}/{x}.jpg',
        tileProvider: _makeTileProvider(tileName),
        maxNativeZoom: 11,
        tms: true,
        evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
        errorTileCallback: (tile, error, stackTrace) {
          debugPrint("$tileName: error: ${tile.imageInfo?.debugLabel ?? "?"}, $error, $stackTrace");
        },
      );
    case MapTileSrc.satellite:
      return TileLayer(
        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        tileProvider: _makeTileProvider(tileName),
        maxNativeZoom: 19,
        minZoom: 2,
        evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
        errorTileCallback: (tile, error, stackTrace) {
          debugPrint("$tileName: error: $tile, $error, $stackTrace");
        },
      );
    // https://docs.openaip.net/?urls.primaryName=Tiles%20API
    // case MapTileSrc.airspace:
    //   return TileLayer(
    //     urlTemplate: 'https://api.tiles.openaip.net/api/data/airspaces/{z}/{x}/{y}.png?apiKey={apiKey}',
    //     tileProvider: _makeTileProvider(tileName),
    //     backgroundColor: Colors.transparent,
    //     // maxZoom: 11,
    //     maxNativeZoom: 11,
    //     minZoom: 7,
    //     additionalOptions: const {"apiKey": aipClientToken},
    //     evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
    //     errorTileCallback: (tile, error, stackTrace) {
    //       debugPrint("$tileName: error: $tile, $error, $stackTrace");
    //     },
    //   );
    // case MapTileSrc.airports:
    //   return TileLayer(
    //     urlTemplate: 'https://api.tiles.openaip.net/api/data/airports/{z}/{x}/{y}.png?apiKey={apiKey}',
    //     tileProvider: _makeTileProvider(tileName),
    //     backgroundColor: Colors.transparent,
    //     maxZoom: 11,
    //     minZoom: 9,
    //     additionalOptions: const {"apiKey": aipClientToken},
    //     evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
    //     errorTileCallback: (tile, error, stackTrace) {
    //       debugPrint("$tileName: error: $tile, $error, $stackTrace");
    //     },
    //   );
    default:
      debugPrint("------ make tile layer ----");
      return TileLayer(
        urlTemplate: "https://tile.opentopomap.org/{z}/{x}/{y}.png",
        // urlTemplate: "https://tile.tracestrack.com/topo__/{z}/{x}/{y}.png?key={apiKey}",
        // fallbackUrl: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
        // urlTemplate: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png", // Use this line to test seeing the elevation map
        tileProvider: _makeTileProvider(tileName),
        maxNativeZoom: 17,
        // minZoom: 2,
        // additionalOptions: const {"apiKey": "d9344714a8fbf28773ce4c955ea8adfb"},
        evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
        errorTileCallback: (tile, error, stackTrace) {
          debugPrint("$tileName: error: $tile, $error, $stackTrace");
        },
      );
  }
}

TileLayer getMapTileLayer(MapTileSrc tileSrc) {
  if (_tileLayersCache.containsKey(tileSrc)) {
    return _tileLayersCache[tileSrc]!;
  } else {
    final newTileLayer = _buildMapTileLayer(tileSrc);
    _tileLayersCache[tileSrc] = newTileLayer;
    return newTileLayer;
  }
}

final Map<MapTileSrc, Image> mapTileThumbnails = {
  MapTileSrc.topo: Image.asset(
    "assets/images/topo.png",
    filterQuality: FilterQuality.high,
    fit: BoxFit.cover,
  ),
  MapTileSrc.sectional: Image.asset(
    "assets/images/sectional.png",
    filterQuality: FilterQuality.high,
    fit: BoxFit.cover,
  ),
  MapTileSrc.satellite: Image.asset(
    "assets/images/satellite.png",
    filterQuality: FilterQuality.high,
    fit: BoxFit.cover,
  ),
  // MapTileSrc.airspace: Image.asset(
  //   "assets/images/sectional.png",
  //   filterQuality: FilterQuality.high,
  //   fit: BoxFit.cover,
  // ),
  // MapTileSrc.airports: Image.asset(
  //   "assets/images/sectional.png",
  //   filterQuality: FilterQuality.high,
  //   fit: BoxFit.cover,
  // )
};

Future initMapCache() async {
  await FMTCObjectBoxBackend().initialise(rootDirectory: (await getApplicationDocumentsDirectory()).path);

  for (final tileSrc in mapTileThumbnails.keys) {
    final tileName = tileSrc.toString().split(".").last;
    final store = FMTCStore(tileName);
    await store.manage.create();
    await store.metadata.set(key: 'sourceURL', value: getMapTileLayer(tileSrc).urlTemplate!);
    // Do a regular purge of old tiles
    store.manage.removeTilesOlderThan(expiry: clock.now().subtract(const Duration(days: 16)));
  }

  await initDemCache();

  mapServiceIsInit = true;
}

String asReadableSize(double value) {
  if (value <= 0) return '0 B';
  final List<String> units = ['B', 'kB', 'MB', 'GB', 'TB'];
  final int digitGroups = (log(value) / log(1024)).round();
  return '${NumberFormat('#,##0.#').format(value / pow(1024, digitGroups))} ${units[digitGroups]}';
}

Future<String> getMapTileCacheSize() async {
  final sum = await FMTCRoot.stats.realSize;
  return asReadableSize(sum);
}

void emptyMapTileCache() {
  // Empty elevation map cache
  const demStore = FMTCStore("dem");
  debugPrint("Clear Map Cache: dem");
  demStore.manage.reset();

  // Empty standard map caches
  for (final tileSrc in mapTileThumbnails.keys) {
    final tileName = tileSrc.toString().split(".").last;
    final store = FMTCStore(tileName);
    debugPrint("Clear Map Cache: $tileName");
    store.manage.reset();
  }
}
