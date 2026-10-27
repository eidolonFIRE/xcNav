import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'package:dart_numerics/dart_numerics.dart' as math;
import 'package:xcnav/datadog.dart';

TileLayer? _demTileLayer;

const demUrlTemplate = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png';

/// Zoom levels sampled from the DEM, coarsest first. Offline areas download all of them.
/// [sampleDem] uses 10 and 12, the glide range any of them.
const demZoomLevels = [9, 10, 11, 12];

/// Decoded tiles kept in memory
const _maxCachedTiles = 60;

/// Tile layer used as options for bulk downloading DEM tiles
TileLayer demDownloadLayer() => TileLayer(urlTemplate: demUrlTemplate);

/// Tile addresses to be fetched.
final Queue<String> _fetchQueue = Queue();

/// Only runs while [_fetchQueue] has work, so it doesn't keep the app awake.
Timer? _fetchTimer;

final Queue<String> _tileCacheQueue = Queue();
final Map<String, ByteData> _tileCacheData = {};
final Map<String, int> _tileCacheWidth = {};

/// Count of tiles loaded into the cache so far. Changes when ground that wasn't loaded may now be.
int demTilesLoaded = 0;

/// Tile [sampleDemAtZoom] last read from. Tile data never changes, so it stays valid even once evicted.
({int x, int y, int z, ByteData data, int width})? _lastTile;

// Digital Elevation Map - service
Future initDemCache() async {
  // init elevation map (dem = digital elevation map)
  const demStore = FMTCStore("dem");
  await demStore.manage.create();
  await demStore.metadata.set(key: 'sourceURL', value: demUrlTemplate);

  // set the layer
  demStore.manage.ready.then((ready) {
    if (ready) {
      _demTileLayer = TileLayer(
          urlTemplate: demUrlTemplate,
          tileProvider: FMTCTileProvider(
              stores: {"dem": BrowseStoreStrategy.readUpdateCreate},
              // Offline map downloads
              otherStoresStrategy: BrowseStoreStrategy.read,
              cachedValidDuration: const Duration(days: 90)));
      _startFetchTimer();
    } else {
      error("DEM store not ready!");
    }
  });
}

void _startFetchTimer() {
  // Nothing to fetch with until the store is ready. It starts the timer once it is.
  if (_demTileLayer == null || _fetchQueue.isEmpty) return;

  _fetchTimer ??= Timer.periodic(Duration(milliseconds: 100), (timer) {
    // Pop one off queue and fetch it

    final pointAddress = _fetchQueue.firstOrNull;
    if (pointAddress == null) {
      timer.cancel();
      _fetchTimer = null;
      return;
    }

    if (!_tileCacheQueue.contains(pointAddress)) {
      final point = pointAddress.split(",").map((e) => int.parse(e)).toList();
      final pointTile = TileCoordinates(point[0], point[1], point[2]);
      // Query the image

      final img = _demTileLayer!.tileProvider.getImage(pointTile, _demTileLayer!);
      final imgStream = img.resolve(ImageConfiguration.empty);
      imgStream.addListener(ImageStreamListener((imgInfo, state) {
        // (DEBUG) debugPrint("Got DEM tile: $state ${imgInfo.toString()}");
        if (!state) {
          imgInfo.image.toByteData().then((data) {
            if (data != null) {
              final w = imgInfo.image.width;

              // store back to cache
              if (!_tileCacheQueue.contains(pointAddress)) {
                _tileCacheWidth[pointAddress] = w;
                _tileCacheData[pointAddress] = data;
                _tileCacheQueue.add(pointAddress);
                demTilesLoaded++;
              }

              // clean cache
              if (_tileCacheQueue.length > _maxCachedTiles) {
                final oldest = _tileCacheQueue.first;
                // (DEBUG) debugPrint("Popping one from DEM cache. $oldest");
                _tileCacheQueue.removeFirst();
                _tileCacheData.remove(oldest);
                _tileCacheWidth.remove(oldest);
              }

              // Good fetch!
              _fetchQueue.remove(pointAddress);
            }
          });
        }
      }, onError: (exception, stackTrace) {
        // Failed fetch (e.g. offline). Drop it so the timer can stop. sampleDem queues it again on a later fix.
        _fetchQueue.remove(pointAddress);
      }));
    } else {
      // Already cached. Drop it so the queue can drain and the timer can stop.
      _fetchQueue.removeFirst();
    }
  });
}

class Point3 {
  final double x;
  final double y;
  final double z;
  Point3(this.x, this.y, this.z);
}

Point3 _unproject(LatLng latlng, int zoom) {
  final double n = pow(2.0, zoom.toDouble()).toDouble();
  final xtile = n * ((latlng.longitude + 180) / 360);
  final ytile = n * (1 - math.asinh(tan(latlng.latitude / 180 * pi)) / pi) / 2;
  return Point3(xtile, ytile, zoom.toDouble());
}

double _sampleByteData(ByteData data, int w, double x, double y) {
  // debugPrint("offset: $x, $y ($s) ( ${(x + y * s) * 4} / ${imgInfo.sizeBytes} )");
  final bitPos = (((x % 1.0) * w).toInt() + (((y % 1.0) * w).toInt() * w).toInt()) * 4;
  final r = data.getUint8(bitPos + 0);
  final g = data.getUint8(bitPos + 1);
  final b = data.getUint8(bitPos + 2);
  // final a = value.getUint8(bitPos + 3);
  // debugPrint("rgba : $r $g $b $a");
  return ((r * 256 + g + b.toDouble() / 256) - 32768);
}

/// Physically plausible ground elevation (meters). Lowest land is ~-430m (Dead Sea), highest ~8849m (Everest).
bool isValidElevation(double elev) => elev > -500 && elev < 9000;

/// Sample the DEM layer. (digital elevation map)
/// Returns elevation in Meters
double? sampleDem(LatLng latlng, bool highRes) => sampleDemAtZoom(latlng, highRes ? 12 : 10);

/// Sample the DEM layer at a specific tile [zoom]. Missing tiles are queued to fetch.
/// Returns elevation in Meters
double? sampleDemAtZoom(LatLng latlng, int zoom) {
  final point = _unproject(latlng, zoom);
  final tileX = point.x.toInt();
  final tileY = point.y.toInt();

  // Same tile as last time. (Grids sample many points in a row from one tile.)
  final last = _lastTile;
  if (last != null && last.x == tileX && last.y == tileY && last.z == zoom) {
    final elev = _sampleByteData(last.data, last.width, point.x, point.y);
    return isValidElevation(elev) ? elev : null;
  }

  final pointAddress = "$tileX,$tileY,$zoom";

  // Check cache first
  final data = _tileCacheData[pointAddress];
  if (data != null) {
    final width = _tileCacheWidth[pointAddress]!;
    _lastTile = (x: tileX, y: tileY, z: zoom, data: data, width: width);
    final elev = _sampleByteData(data, width, point.x, point.y);
    // Reject no-data / corrupt pixels (e.g. rgb 0,0,0 decodes to -32768m) and deep bathymetry.
    return isValidElevation(elev) ? elev : null;
  } else {
    if (!_fetchQueue.contains(pointAddress)) {
      // Schedule this tile to be pulled
      // (DEBUG) debugPrint("Queue fetch tile: $pointAddress");
      _fetchQueue.add(pointAddress);
      _startFetchTimer();
    } else {
      // (DEBUG) debugPrint("Already queued for fetch: $pointAddress");
    }
  }

  // We didn't have it this time, try again when it's loaded.
  return null;
}
