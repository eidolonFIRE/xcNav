# MapLibre migration (proof of concept)

`flutter_map` (+ `flutter_map_tile_caching`, `flutter_map_dragmarker`, `flutter_map_line_editor`) is replaced by
[`maplibre_gl`](https://pub.dev/packages/maplibre_gl) 0.27.

## Base maps

| Layer     | Source                                                                 |
|-----------|------------------------------------------------------------------------|
| Topo      | MapTiler `topo-v4` vector style (hillshade, contours, 3D buildings)     |
| Satellite | MapTiler `satellite-v4` style (imagery + labels)                        |
| Sectional | vfrmap.com raster tiles, served to MapLibre by a local tile server      |

The MapTiler key lives in `lib/secrets.dart` as `maptilerKey` (see `secrets.dart.example`).

## How it fits together

- `lib/views/map/xc_map.dart` – `XcMap` wraps `MapLibreMap`. It owns the style, the base map opacity (a white
  background layer over the base map), and the app's line/area overlays (`ShapeLayer`s → one GeoJSON source each,
  drawn natively).
- `lib/views/map/map_markers.dart` – markers are still Flutter widgets (`MarkerLayer`/`MapMarker`). A `Flow` places
  them using our own copy of MapLibre's camera math (`lib/models/map_camera.dart`), so they stay put under rotation
  and tilt (checked against native `toScreenLocation`: < 0.5 px).
- `lib/views/map/poly_editor.dart` – drag handles for paths, measurements, and offline polygons.
- Hit testing (tap / long press on waypoint paths) is done in Dart against the camera, not with native queries.
- `lib/widgets/static_map.dart` – lists (flight log cards, offline area cards) and the wind dialog draw previews in
  Flutter from cached raster tiles instead of spinning up a native map per card.
- `lib/services/tile_cache.dart` – our own raster tile cache (sectional, elevation, preview tiles), with browse
  and offline-area stores. `lib/services/local_tile_server.dart` serves it to MapLibre on `127.0.0.1:47621`
  (Android network security config + iOS `NSAllowsLocalNetworking` allow this).
- Zoom numbers are MapLibre's (512px tiles), one less than flutter_map's for the same scale. Thresholds were shifted.

## Offline areas

- MapTiler layers download as MapLibre offline regions (style, fonts, tiles). Sectional and elevation tiles download
  through our tile cache, throttled per server like before.
- Areas are stored under a new prefs key (`offlineMaps.v2.areas`). Areas downloaded by older builds are not
  migrated (their tiles are in the FMTC store this build can't read) and are left untouched for older builds.

## Not done / limited (revisit)

- **3D terrain:** MapLibre Native (Android/iOS) has no 3D terrain yet (Terrain3D is still on a feature branch;
  `setTerrain` throws on mobile). "3D" is a tilted perspective view plus hillshade. `XcMap` already calls
  `setTerrain` (with MapTiler's terrain-rgb) and ignores the error, so it should light up once native support ships.
- **Marker lag:** Flutter markers trail the native map by about a frame during fast pans. If it bothers anyone, move
  the busy layers (airports, weather stations) to native symbol layers.
- **Offline regions are rectangles:** polygon areas download their bounding box for MapTiler layers.
- **Resume after restart:** a paused MapLibre region can only be resumed in the same session (plugin limitation).
  After a restart it starts over.
- **Offline size estimates** for MapTiler layers are rough (`defaultAvgTileBytes`, `offlineRegionOverheadBytes`,
  measured from small Bay Area downloads).
- **Old FMTC data:** `<documents>/fmtc` (browse cache + old offline areas) is orphaned. Add a cleanup when this ships.
- **iOS** hasn't been built or run (developed on Windows).
- **MapTiler free key:** the Static Maps API is refused (403), so previews use raster tiles instead.
- **Style warnings:** MapLibre Native logs warnings for GL JS-only properties in MapTiler styles (`text-overlap`,
  `icon-overlap`). Harmless.

## GL JS plugins

The [plugin list](https://maplibre.org/maplibre-gl-js/docs/plugins/) is for MapLibre GL JS (web). None of them run in
MapLibre Native on Android/iOS, so the equivalents are in Dart:

| Plugin                                    | Here                                                       |
|-------------------------------------------|------------------------------------------------------------|
| mapbox-gl-draw, Terra Draw, geoman        | `MapPolyEditor` (paths, measurement, offline polygons)      |
| maplibre-gl-measures                      | existing measurement mode                                  |
| maplibre-gl-opacity                       | base map opacity (`XcMap.opacity`)                          |
| map-gl-offline                            | MapLibre offline regions + `TileCache`                      |
| mapbox-gl-elevation                       | existing `dem_service.dart` (could switch to MapTiler terrain-rgb) |
| maplibre-contour                          | not needed, `topo-v4` has contours                          |
| geojson-map-fit-mercator                  | `MapCamera.fit`                                             |
| maplibre-gl-export / map-to-image         | `MapLibreMapController.takeSnapshot()` if ever needed       |
| PMTiles                                   | MapLibre Native reads `pmtiles://` itself, an option for hosting the sectional |
