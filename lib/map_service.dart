import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
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

/// Topo and satellite come from Mapbox (Outdoors, Satellite Streets): Mapbox's offline downloads only take its own
/// tiles. MapTiler's styles still work online with this set to true, but offline areas then only get the sectional.
const bool useMapTilerStyles = false;

/// MapTiler hosted styles (vector topo, satellite imagery with labels)
const Map<MapTileSrc, String> _maptilerStyleIds = {
  MapTileSrc.topo: "topo-v4",
  MapTileSrc.satellite: "hybrid-v4",
};

/// Mapbox hosted styles, the alternative to MapTiler's
const Map<MapTileSrc, String> _mapboxStyles = {
  MapTileSrc.topo: "mapbox://styles/mapbox/outdoors-v12",
  MapTileSrc.satellite: "mapbox://styles/mapbox/satellite-streets-v12",
};

/// Hosted style for a MapTiler base map. The sectional has none (see [mapStyleUri]).
String? maptilerStyleUrl(MapTileSrc src) {
  final id = _maptilerStyleIds[src];
  return id == null ? null : "https://api.maptiler.com/maps/$id/style.json?key=$maptilerKey";
}

/// Raster DEM used for terrain (3D) on MapTiler maps
String get maptilerTerrainUrl => "https://api.maptiler.com/tiles/terrain-rgb-v2/tiles.json?key=$maptilerKey";

/// Elevation tiles the map draws 3D terrain with (TileJSON). MapTiler's topo style has the same ones built in.
String get terrainTilesetUrl => useMapTilerStyles ? maptilerTerrainUrl : "mapbox://mapbox.mapbox-terrain-dem-v1";

/// 3D terrain is drawn this much taller than it really is, so it reads better from above
const double terrainExaggeration = 1.5;

/// Elevation data for 3D terrain: the source id, and the source to add when the style doesn't already have it.
({String id, Map<String, dynamic>? source}) terrainSourceFor(MapTileSrc src) {
  if (src == MapTileSrc.topo && useMapTilerStyles) {
    // MapTiler's topo style ships with a DEM (it draws its hillshade from it)
    return (id: "terrain_rgb", source: null);
  }
  return (
    id: "xc_terrain",
    source: {"type": "raster-dem", "url": terrainTilesetUrl, "tileSize": 512, if (!useMapTilerStyles) "maxzoom": 14},
  );
}

/// Our changes to a hosted style, applied once it loads: layer id → property (paint or layout) → value.
Map<String, Map<String, Object>> styleOverridesFor(MapTileSrc src) {
  if (src != MapTileSrc.topo) return const {};
  return useMapTilerStyles ? topoStyleOverrides : outdoorsStyleOverrides;
}

/// Layers we add to a hosted style once it loads, each below the [below] layer (on top when null).
List<({Map<String, Object> layer, String? below})> styleAdditionsFor(MapTileSrc src) =>
    src == MapTileSrc.topo && !useMapTilerStyles ? [(layer: outdoorsHillshade(), below: "hillshade")] : const [];

/// Mapbox Outdoors, a bit bolder:
/// - its faint shading polygons ("hillshade") swapped for real relief shading, see [outdoorsHillshade]
/// - contour lines more solid (theirs are 15 to 50% opaque)
const Map<String, Map<String, Object>> outdoorsStyleOverrides = {
  "hillshade": {"visibility": "none"},
  "contour-line": {
    "line-opacity": [
      "interpolate",
      ["linear"],
      ["zoom"],
      11,
      [
        "match",
        ["get", "index"],
        [1, 2],
        0.25,
        0.45
      ],
      13,
      [
        "match",
        ["get", "index"],
        [1, 2],
        0.45,
        0.75
      ]
    ],
  },
};

/// Relief shading from the elevation tiles 3D terrain uses (so it works offline too), with the deep shadows tuned on
/// MapTiler's topo. Mapbox caps hillshade-exaggeration at 1.
Map<String, Object> outdoorsHillshade() => {
      "id": "xc_hillshade",
      "type": "hillshade",
      "source": terrainSourceFor(MapTileSrc.topo).id,
      "paint": {
        "hillshade-exaggeration": [
          "interpolate",
          ["linear"],
          ["zoom"],
          0,
          0.5,
          12,
          0.8,
          22,
          1.0
        ],
        "hillshade-shadow-color": "hsl(220, 20%, 20%)",
        "hillshade-highlight-color": "hsl(51, 12%, 83%)",
        "hillshade-accent-color": "hsl(51, 67%, 56%)",
      },
    };

/// Topo, a bit bolder than MapTiler's own:
/// - deeper hillshade (theirs: exaggeration 0.3 to 0.6, 50% gray shadows). Mapbox caps hillshade-exaggeration at 1.
/// - darker contour lines (theirs: hsl(22, 35%, 55%))
const Map<String, Map<String, Object>> topoStyleOverrides = {
  "Hillshade": {
    "hillshade-exaggeration": [
      "interpolate",
      ["linear"],
      ["zoom"],
      0,
      0.5,
      12,
      0.8,
      22,
      1.0
    ],
    "hillshade-shadow-color": "hsl(220, 20%, 20%)",
  },
  "Contour index": {"line-color": "hsl(22, 35%, 42%)"},
  "Contour": {"line-color": "hsl(22, 35%, 42%)"},
};

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
final topoPreviewTiles = useMapTilerStyles
    ? RasterTileSource(
        name: "topo_raster",
        urlBuilder: (z, x, y) => "https://api.maptiler.com/maps/topo-v4/256/$z/$x/$y.png?key=$maptilerKey",
        maxNativeZoom: 19,
        ext: "png",
        contentType: "image/png",
      )
    : RasterTileSource(
        name: "outdoors_raster",
        urlBuilder: (z, x, y) =>
            "https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/256/$z/$x/$y?access_token=$mapboxAccessToken",
        maxNativeZoom: 19,
        ext: "png",
        contentType: "image/png",
      );

final satellitePreviewTiles = useMapTilerStyles
    ? RasterTileSource(
        name: "satellite_raster",
        urlBuilder: (z, x, y) => "https://api.maptiler.com/tiles/satellite-v2/$z/$x/$y.jpg?key=$maptilerKey",
        maxNativeZoom: 20,
        tileSize: 512,
        ext: "jpg",
        contentType: "image/jpeg",
      )
    : RasterTileSource(
        name: "mapbox_satellite_raster",
        urlBuilder: (z, x, y) => "https://api.mapbox.com/v4/mapbox.satellite/$z/$x/$y.jpg?access_token=$mapboxAccessToken",
        maxNativeZoom: 19,
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

/// Style URI for a base map. The sectional style is built here and served by the local tile server.
String mapStyleUri(MapTileSrc src) {
  if (src == MapTileSrc.sectional) return localTileServer.styleUrl(MapTileSrc.sectional.name);
  return (useMapTilerStyles ? maptilerStyleUrl(src) : _mapboxStyles[src])!;
}

/// Raster style around the sectional chart tiles
String sectionalStyleJson() {
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

  // Map SDK needs the token before any map is made
  mb.MapboxOptions.setAccessToken(mapboxAccessToken);

  tileCache.register(sectionalTiles);
  tileCache.register(topoPreviewTiles);
  tileCache.register(satellitePreviewTiles);
  await tileCache.init();
  localTileServer.styles[MapTileSrc.sectional.name] = sectionalStyleJson;
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
  int digitGroups = (log(value) / log(1024)).round();
  // Would show as "0 GB": use the smaller unit
  if (digitGroups > 0 && value / pow(1024, digitGroups) < 0.05) digitGroups--;
  return '${NumberFormat('#,##0.#').format(value / pow(1024, digitGroups))} ${units[digitGroups]}';
}

/// Our raster tile cache. (The map SDK doesn't report the size of its own cache.)
Future<String> getMapTileCacheSize() async {
  return asReadableSize((await tileCache.browseStats()).bytes.toDouble());
}

void emptyMapTileCache() {
  debugPrint("Clear Map Cache: raster tiles");
  tileCache.clearBrowseCache();

  debugPrint("Clear Map Cache: map SDK");
  mb.MapboxMapsOptions.clearData().catchError((e) => debugPrint("Clearing map SDK cache failed: $e"));

  // Empty airspace / airports
  debugPrint("Clear Map Cache: OpenAIP");
  openAipService.clear();
}
