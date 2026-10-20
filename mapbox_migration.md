# Mapbox migration (proof of concept)

`flutter_map` (+ `flutter_map_tile_caching`, `flutter_map_dragmarker`, `flutter_map_line_editor`) is replaced by
[`mapbox_maps_flutter`](https://pub.dev/packages/mapbox_maps_flutter) 3.33 (Mapbox Maps SDK 11.33).

A first pass used `maplibre_gl`. MapLibre Native has no 3D terrain on Android/iOS, so it moved to Mapbox, which does.

## Setup

- `lib/secrets.dart` needs `mapboxAccessToken` (a public `pk.` token). The token is set in code at startup
  (`initMapCache` → `MapboxOptions.setAccessToken`). It ships inside the app, so give it public scopes only.
  `maptilerKey` is still needed to compile, but is only used with `useMapTilerStyles` (see below).
- Android: the plugin only applies `kotlin-android` on AGP < 9, expecting AGP's built-in Kotlin after that. This app
  turns built-in Kotlin off (`android.builtInKotlin=false`), so `android/build.gradle` applies
  `org.jetbrains.kotlin.android` to `mapbox_maps_flutter_mobile` itself. Drop that block once the plugin or this app
  moves to built-in Kotlin.

## Base maps

| Layer     | Style                                                           | 3D terrain                       |
|-----------|-----------------------------------------------------------------|----------------------------------|
| Topo      | Mapbox `outdoors-v12`, with our tweaks (below)                  | Mapbox `mapbox-terrain-dem-v1`   |
| Satellite | Mapbox `satellite-streets-v12`                                  | Mapbox `mapbox-terrain-dem-v1`   |
| Sectional | vfrmap.com raster tiles, style + tiles from a local tile server | Mapbox `mapbox-terrain-dem-v1`   |

XcMap adds the terrain source to every style.

**Why Mapbox's styles, not MapTiler's:** Mapbox's offline downloads (`TileStore`) only take Mapbox-hosted tiles. With
MapTiler's styles, a download finishes with nothing in it, and MapTiler TileJSON is refused ("must be a mapbox: URL to
TileJSON"). MapTiler's `topo-v4` / `hybrid-v4` still work online: set `useMapTilerStyles = true` in
`lib/map_service.dart`. Offline areas then only get the sectional and elevation; topo / satellite end up "Incomplete".

**Topo tweaks** (`styleOverridesFor` / `styleAdditionsFor` in `lib/map_service.dart`, applied after each style load):
- Outdoors' own shading (faint vector polygons, layer `hillshade`) is hidden. A real relief shading layer (`xc_hillshade`)
  takes its place, drawn from the 3D terrain's elevation tiles, with the deep shadows tuned earlier on MapTiler's topo:
  exaggeration 0.5 to 1, dark blue-gray shadows.
- Contour lines are more solid: 25 to 75% opaque (theirs are 15 to 50%).
- MapTiler's topo has its own set (`topoStyleOverrides`), used with `useMapTilerStyles`.

The sectional is served on `127.0.0.1:47621` (`/styles/sectional.json` and `/tiles/sectional/z/x/y`). The Android
network security config and iOS `NSAllowsLocalNetworking` allow cleartext to localhost. Chart tiles stop at z11, so
they're stretched when zoomed in further, same as before.

## 3D

- The main map is always 3D: terrain plus a sky layer, starting at 60° tilt. Gestures tilt it anywhere from 0° to 75°.
  (There's no 3D button any more.) The other maps (plan editor, plan cards, log replay) stay flat.
- Terrain is drawn 1.5 times as tall as it really is (`terrainExaggeration` in `lib/map_service.dart`), on every base map.
- The projection is pinned to mercator; the overlays assume it.
- Lines and areas (paths, airspace, TFRs, traces) are native layers, so Mapbox drapes them over the terrain.
- Markers are native too (see Markers below), so Mapbox stands them on the terrain.
- Mapbox gets the angle of markers that turn with the map wrong when they stand up on 3D terrain (90° off). Those
  (heading arrows, chevrons, wind arrows, ADS-B icons) lie flat on the map instead. Upright markers are fine.
- The few things that stay Flutter widgets (drag handles) use `MapCamera`, which follows Mapbox's camera including
  ground height: `centerElevation` plus each point's elevation from `dem_service.dart`, times the exaggeration.
  Checked against native `coordinateForPixel` on Mt. Diablo at 60° tilt and 1.5x exaggeration, with MapTiler's terrain
  (not measured again with Mapbox's):

  | Zoom | Error | Error if drawn flat |
  |------|-------|---------------------|
  | 11   | 0.3px | 10px                |
  | 12   | 1px   | 52px                |
  | 13   | 5px   | 48px                |

  What's left is the elevation data: our DEM (AWS Terrarium) and the one the map draws differ by 10-20m on steep slopes,
  and the exaggeration scales that up too.
- Those sample DEM tiles at about the map zoom minus one (`terrainDemZoom`), and only near the view. So a screen of
  them takes a handful of tiles. The DEM memory cache is now least-recently-used, so busy tiles stay loaded.

## Markers

Markers are drawn by Mapbox (symbol layers), so they move in step with the map. Flutter widgets over the map trail it
by a frame or two while panning. `lib/views/map/map_symbols.dart`:

- A `MapSymbol` is still built from a Flutter widget. The widget is drawn once, off screen, into an image (cropped to
  what's visible), and the image is shared by every symbol with the same `imageKey`. Pictures are cached across maps,
  up to 32MB. Bundled svg/png assets are loaded first, and `MapSymbol.precache` loads others (eg. avatars).
- It's only a picture, so gestures inside the widget do nothing. `onTap` / `onLongPress` come from Mapbox tap
  interactions on the layer. Symbols without handlers let taps through to the map.
- `XcMap(symbols: [...])` takes `SymbolLayer`s, drawn above the shapes in list order. Each is one GeoJSON source +
  symbol layer, updated when its data changes. Images no symbol uses any more are removed from the style.
- Labels are part of the pictures (keyed by their text), so they look the same on every base map. Mapbox's own text
  needs fonts from the style, which the sectional doesn't have.
- Zoom limits are the layer's `minZoom` (airports from 7, their codes from 9, weather from 6), so zooming doesn't
  rebuild anything.
- Native: airports, waypoints, chevrons to the next waypoint, weather stations, ADS-B traffic, group pilots, fuel
  warning, my position, measurement labels, plan editor / plan card / log replay markers.
- Still Flutter widgets: things you drag (the waypoint being moved, path and measurement handles), and markers on
  `StaticMap` previews, which have no map engine.
- In widget tests (fake map), symbols are drawn as Flutter markers instead, so tests can find and tap them.

## Offline maps

Main menu → Offline Maps, as before: pick an area (the visible area or a polygon) and layers.
`lib/services/offline_map_service.dart`:

- Topo and satellite are Mapbox tile regions (`TileStore.loadTileRegion`) with their style pack (style, fonts, icons).
  3D terrain is one more region (the terrain tiles, z1 to 12), always included. Regions follow the polygon.
  The map uses them by itself when there's no network.
- The sectional and our elevation tiles (AGL, elevation plot) download through our tile cache, as before. The local tile
  server reads the area's sectional tiles when there's no network, whatever the current chart cycle.
- The sectional only goes to chart zoom 10 (`offlineMaxZoom`), one short of its full detail (11). Offline it's sharp up
  to about map zoom 9, then blurry: at the main map's usual zoom 11, Mapbox stretches the zoom 10 tiles. Going to 11
  would take about 4 times the sectional tiles (still small next to topo / satellite).
- Pause: Mapbox has no cancel. Loading the region again with no network allowed cancels the load in progress.
  Resume, also after a restart, loads the region again and Mapbox fetches only what's missing.
- Delete removes the area's regions (and style packs no other area needs). Mapbox frees that space only once it needs
  it, so the tile store's disk quota is then set to 0 and back, which frees it right away. That doesn't touch tiles other
  areas still use. Regions and style packs no area knows about (eg. left by older builds) are removed at startup.
- Size estimates: Mapbox's own (`estimateTileRegion`) when it gives a finite error margin (small areas, about ±200%).
  For big areas it only guesses (infinite margin, sometimes 0 bytes), so ours is used: per-tile averages plus each
  region's fixed overhead (`defaultAvgTileBytes`, `offlineRegionOverheadBytes` in `lib/models/offline_area.dart`).
- Sizes measured on a ~10km square near Danville (Oct 2026): topo 68MB, satellite 171MB, terrain 65MB. That's mostly
  low zoom tile packs, which nearby areas share: a second topo area near San Jose took 11MB more on disk. The size
  shown on each area counts shared packs, so side by side areas add up to more than they use.
- Areas are stored under the prefs key `offlineMaps.v2.areas`. Areas downloaded by flutter_map builds aren't migrated.
  Their tiles are in the FMTC store, which this build can't read.

Checked on the Android emulator: topo, satellite, and sectional downloads, progress, pause / resume, delete (space
freed, the other area still fine), and the map with the network off: vector map, 3D terrain, relief shading, contours,
and the sectional (from the area's tiles, with the browse cache cleared).

**Offline terrain needs one online map view first.** 3D terrain and the relief shading come from a source XcMap adds,
and Mapbox needs that source's TileJSON before it can use the downloaded terrain tiles. Mapbox doesn't keep TileJSON for
sources added at runtime in the offline download, only in its ambient cache: any online map view caches it, and it's
used even when stale. So after Settings → "Clear Map Cache", open the map once online before relying on offline
terrain. (Without it, the map still works offline, just flat and without shading.) The real fix is a Mapbox Studio
style that includes the terrain source, so its style pack carries the TileJSON.

## How it fits together

- `lib/views/map/xc_map.dart` – `XcMap` wraps Mapbox's `MapWidget`. It owns the style, the base map opacity (a
  white background layer over the base map), terrain, and the app's line/area overlays (`ShapeLayer`s → one GeoJSON
  source each).
  - Loading a style resets the camera to the style's default. XcMap puts its camera back after every style load.
  - Partial camera moves build on the animation in flight. Following GPS doesn't cut short a tilt or zoom.
- `lib/views/map/map_symbols.dart` – native markers, see above. `lib/views/map/map_layers.dart` builds them.
- `lib/views/map/map_markers.dart` – Flutter markers (`MarkerLayer`/`MapMarker`) for what's dragged, placed by a `Flow`
  using `lib/models/map_camera.dart`.
- `lib/views/map/poly_editor.dart` – drag handles for paths and measurements.
- Taps and long presses come from Mapbox (`TapInteraction` / `LongTapInteraction`), so the position is on the
  terrain. Hit testing waypoint paths is done in Dart against the camera.
- `lib/widgets/static_map.dart` – flight log cards, offline area cards, and the wind dialog draw previews in Flutter from
  cached raster tiles (Mapbox's Static Tiles / Raster Tiles APIs) instead of a native map per card.
- `lib/services/tile_cache.dart` – our raster tile cache (sectional, elevation, preview tiles).
- Mapbox keeps its own ambient cache. Settings → "Clear Map Cache" clears both (`MapboxMapsOptions.clearData()`); offline
  areas aren't affected. The size shown only counts ours.
- Zoom numbers are Mapbox's (512px tiles), one less than flutter_map's for the same scale. Thresholds were shifted.
- Mapbox's logo and attribution stay on the map (required by Mapbox's terms), bottom left, beside the map controls
  (`XcMap.ornamentMargin`). Mapbox's compass and scale bar are off; the app has its own.

## Billing and limits

- Mapbox bills the mobile SDK per monthly active user, with a free tier (25,000 MAU per month when this was written;
  check current pricing). Previews use Mapbox's Static Tiles and Raster Tiles APIs, which have their own free tiers.
- Offline: by default Mapbox allows 750 tile packs across all regions. A small area takes about 30 packs for topo and
  terrain. Past the limit, downloads fail until areas are deleted.
- MapTiler isn't used unless `useMapTilerStyles` is on.

## Not done / limited (revisit)

- **Offline terrain after clearing the cache** – see Offline maps.
- **iOS** hasn't been built or run (developed on Windows).
- **Checked on an Android emulator:**
  - topo, satellite, and sectional, flat and in 3D
  - follow mode with 3D
  - long press, plan card, plan editor
  - native markers: airports (tap for info), pins (tap to select, long press to drag), heading arrow, measurement
    labels, style switches
  - offline areas, see above
- **Not checked:** log replay (the emulator had no logs); weather station, ADS-B, group pilot, and fuel warning markers
  (no data on the emulator).
- **Marker pictures:** labels that change often (ADS-B and pilot relative altitude) get a new picture per value. Fine
  for a handful of aircraft. Mapbox's own text (with fonts added to the sectional style) would scale better.
- **Old FMTC data:** `<documents>/fmtc` (browse cache + old offline areas) is orphaned. Add a cleanup when this ships.

## GL JS plugins

The [MapLibre GL JS plugin list](https://maplibre.org/maplibre-gl-js/docs/plugins/) is for the web. None of them run
in the native SDKs, so the equivalents are in Dart or Mapbox:

| Plugin                                 | Here                                                              |
|----------------------------------------|-------------------------------------------------------------------|
| mapbox-gl-draw, Terra Draw, geoman     | `MapPolyEditor` (paths, measurement)                              |
| maplibre-gl-measures                   | existing measurement mode                                         |
| maplibre-gl-opacity                    | base map opacity (`XcMap.opacity`)                                |
| map-gl-offline                         | Mapbox `TileStore` / `OfflineManager` (offline areas)             |
| mapbox-gl-elevation                    | `dem_service.dart`, or Mapbox's `getElevation` while terrain is on |
| maplibre-contour                       | not needed, the styles have contours                              |
| geojson-map-fit-mercator               | `MapCamera.fit`                                                   |
| maplibre-gl-export / map-to-image      | Mapbox `snapshot()` if ever needed                                |
