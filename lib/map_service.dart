import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/dem_service.dart';
import 'package:xcnav/secrets.dart';
import 'package:xcnav/services/local_tile_server.dart';
import 'package:xcnav/services/openaip_service.dart';
import 'package:xcnav/services/tile_cache.dart';

/// Base maps. Stored in settings by index, so only ever append.
enum MapTileSrc {
  topo,
  sectional,
  satellite,
}

bool mapServiceIsInit = false;

/// Restarts the local tile server if the OS closed it while we were in the background
AppLifecycleListener? _lifecycleListener;

bool _fetchingVfrVersion = false;
DateTime? _lastVfrFetch;
String? _vfrVersion;

/// Current VFR sectional chart cycle (part of the sectional tile URL)
String? get vfrVersion => _vfrVersion;

/// MapTiler hosted styles (vector topo, satellite imagery with labels)
const Map<MapTileSrc, String> _maptilerStyleIds = {
  MapTileSrc.topo: "topo-v4",
  MapTileSrc.satellite: "satellite-v4",
};

/// Hosted MapLibre style for a MapTiler base map. The sectional has none (see [mapStyleString]).
String? maptilerStyleUrl(MapTileSrc src) {
  final id = _maptilerStyleIds[src];
  return id == null ? null : "https://api.maptiler.com/maps/$id/style.json?key=$maptilerKey";
}

/// Raster DEM used for terrain (3D) on MapTiler maps
String get maptilerTerrainUrl => "https://api.maptiler.com/tiles/terrain-rgb-v2/tiles.json?key=$maptilerKey";

/// Sectional chart tiles. vfrmap.com serves TMS tiles at `{z}/{y}/{x}`.
final sectionalTiles = RasterTileSource(
  name: "sectional",
  urlBuilder: (z, x, y) => "https://vfrmap.com/${_vfrVersion ?? "20240711"}/tiles/vfrc/$z/${(1 << z) - 1 - y}/$x.jpg",
  maxNativeZoom: 11,
  ext: "jpg",
  contentType: "image/jpeg",
  version: () => _vfrVersion,
  // Old chart cycles disappear from the server
  onNotFound: () {
    if (_lastVfrFetch == null || clock.now().difference(_lastVfrFetch!) > const Duration(minutes: 10)) {
      fetchVFRversion();
    }
  },
);

/// Raster renders of the topo style, for static previews (lists can't afford a live map per card).
final topoPreviewTiles = RasterTileSource(
  name: "topo_raster",
  urlBuilder: (z, x, y) => "https://api.maptiler.com/maps/topo-v4/256/$z/$x/$y.png?key=$maptilerKey",
  maxNativeZoom: 19,
  ext: "png",
  contentType: "image/png",
);

final satellitePreviewTiles = RasterTileSource(
  name: "satellite_raster",
  urlBuilder: (z, x, y) => "https://api.maptiler.com/tiles/satellite-v2/$z/$x/$y.jpg?key=$maptilerKey",
  maxNativeZoom: 20,
  tileSize: 512,
  ext: "jpg",
  contentType: "image/jpeg",
);

/// Raster tiles that look like [src], for static previews
RasterTileSource previewTilesFor(MapTileSrc src) {
  switch (src) {
    case MapTileSrc.topo:
      return topoPreviewTiles;
    case MapTileSrc.sectional:
      return sectionalTiles;
    case MapTileSrc.satellite:
      return satellitePreviewTiles;
  }
}

/// MapLibre `styleString` for a base map: a style URL, or raw style JSON for the sectional.
String mapStyleString(MapTileSrc src) {
  final url = maptilerStyleUrl(src);
  if (url != null) return url;
  return jsonEncode({
    "version": 8,
    "name": "Sectional",
    "sources": {
      "sectional": {
        "type": "raster",
        "tiles": [localTileServer.tileUrl(sectionalTiles.name)],
        "tileSize": 256,
        "maxzoom": sectionalTiles.maxNativeZoom,
        "attribution": "FAA charts via vfrmap.com",
      }
    },
    "layers": [
      {
        "id": "background",
        "type": "background",
        "paint": {"background-color": "#ffffff"}
      },
      {"id": "sectional", "type": "raster", "source": "sectional"}
    ],
  });
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
};

Future fetchVFRversion() async {
  if (!_fetchingVfrVersion) {
    _fetchingVfrVersion = true;
    _lastVfrFetch = clock.now();
    try {
      final resp = await http.get(Uri.parse("https://vfrmap.com/js/map.js?1"));
      if (resp.statusCode == 200) {
        final dateMatch = RegExp(r"var [\w]{1,2}='(20[\d]{6})';").firstMatch(resp.body);
        final date = dateMatch?.group(1);
        if (date != null) {
          _vfrVersion = date;
          debugPrint("Fetched VFR map version: $_vfrVersion");
          SharedPreferences.getInstance().then((value) => value.setString("vfrVersion", date));
        }
      }
    } catch (e) {
      debugPrint("Fetching VFR map version failed: $e");
    } finally {
      _fetchingVfrVersion = false;
    }
  }
}

Future initVFRversion() async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString("vfrVersion");
  if (cached != null) {
    _vfrVersion = cached;
    debugPrint("Loaded VFR map version: $_vfrVersion");
  } else {
    fetchVFRversion();
  }
}

Future initMapCache() async {
  await initVFRversion();

  tileCache.register(sectionalTiles);
  tileCache.register(topoPreviewTiles);
  tileCache.register(satellitePreviewTiles);
  await tileCache.init();
  await localTileServer.ensureRunning();
  _lifecycleListener ??= AppLifecycleListener(onResume: localTileServer.ensureRunning);

  await initDemCache();

  // Expired tiles are kept a while as an offline fallback, then cleared out.
  Future.delayed(const Duration(seconds: 30), () => tileCache.purge());

  mapServiceIsInit = true;
}

String asReadableSize(double value) {
  if (value <= 0) return '0 B';
  final List<String> units = ['B', 'kB', 'MB', 'GB', 'TB'];
  final int digitGroups = (log(value) / log(1024)).round();
  return '${NumberFormat('#,##0.#').format(value / pow(1024, digitGroups))} ${units[digitGroups]}';
}

/// Browse caches: our raster tiles plus MapLibre's database (which also holds offline regions).
Future<String> getMapTileCacheSize() async {
  int bytes = (await tileCache.browseStats()).bytes;
  try {
    final dbPath = await ml.getOfflineDatabasePath();
    if (dbPath != null) bytes += await File(dbPath).length();
  } catch (e) {
    debugPrint("MapLibre database size unavailable: $e");
  }
  return asReadableSize(bytes.toDouble());
}

void emptyMapTileCache() {
  debugPrint("Clear Map Cache: raster tiles");
  tileCache.clearBrowseCache();

  // Leaves offline regions alone
  debugPrint("Clear Map Cache: MapLibre ambient cache");
  ml.clearAmbientCache().catchError((e) => debugPrint("Clearing MapLibre cache failed: $e"));

  // Empty airspace / airports
  debugPrint("Clear Map Cache: OpenAIP");
  openAipService.clear();
}
