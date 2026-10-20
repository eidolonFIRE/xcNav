import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:dart_numerics/dart_numerics.dart' as math;

import 'package:xcnav/services/tile_cache.dart';

const demUrlTemplate = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png';

/// Elevation tiles (terrarium encoding)
final demTileSource = RasterTileSource(
  name: "dem",
  urlBuilder: (z, x, y) => demUrlTemplate
      .replaceFirst("{z}", z.toString())
      .replaceFirst("{x}", x.toString())
      .replaceFirst("{y}", y.toString()),
  maxNativeZoom: 15,
  ext: "png",
  contentType: "image/png",
  maxAge: const Duration(days: 90),
);

/// Zoom levels sampled by [sampleDem]
const demZoomLevels = [10, 12];

bool _demReady = false;

/// Tile addresses to be fetched.
final Queue<String> _fetchQueue = Queue();

/// Only runs while [_fetchQueue] has work, so it doesn't keep the app awake.
bool _fetching = false;

/// Bumped whenever a tile is loaded, so anything waiting on [sampleDem] can try again.
final ValueNotifier<int> demTilesLoaded = ValueNotifier(0);

final Queue<String> _tileCacheQueue = Queue();
final Map<String, ByteData> _tileCacheData = {};
final Map<String, int> _tileCacheWidth = {};

// Digital Elevation Map - service
Future initDemCache() async {
  tileCache.register(demTileSource);
  _demReady = true;
  _startFetching();
}

/// Decode a PNG tile to raw RGBA
Future<(ByteData, int)?> _decodeTile(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = frame.image.width;
    frame.image.dispose();
    return data == null ? null : (data, width);
  } finally {
    codec.dispose();
  }
}

void _startFetching() {
  // Nothing to fetch with until the cache is ready. It starts fetching once it is.
  if (!_demReady || _fetching || _fetchQueue.isEmpty) return;
  _fetching = true;
  _fetchLoop().whenComplete(() => _fetching = false);
}

Future _fetchLoop() async {
  while (_fetchQueue.isNotEmpty) {
    final pointAddress = _fetchQueue.first;
    if (_tileCacheQueue.contains(pointAddress)) {
      // Already cached. Drop it so the queue can drain.
      _fetchQueue.removeFirst();
      continue;
    }

    final point = pointAddress.split(",").map((e) => int.parse(e)).toList();
    try {
      final bytes = await tileCache.getTile(demTileSource, point[2], point[0], point[1]);
      final decoded = bytes == null ? null : await _decodeTile(bytes);
      if (decoded != null && !_tileCacheQueue.contains(pointAddress)) {
        _storeTile(pointAddress, decoded.$1, decoded.$2);
      }
    } catch (e) {
      debugPrint("DEM tile $pointAddress failed: $e");
    }
    // Good or failed fetch (e.g. offline), drop it. sampleDem queues it again on a later fix.
    _fetchQueue.remove(pointAddress);
  }
}

void _storeTile(String pointAddress, ByteData data, int width) {
  _tileCacheQueue.remove(pointAddress);
  _tileCacheData[pointAddress] = data;
  _tileCacheWidth[pointAddress] = width;
  _tileCacheQueue.add(pointAddress);

  // clean cache: least recently used goes first
  if (_tileCacheQueue.length > 30) {
    final oldest = _tileCacheQueue.removeFirst();
    _tileCacheData.remove(oldest);
    _tileCacheWidth.remove(oldest);
  }
  demTilesLoaded.value++;
}

/// Put a decoded tile (raw RGBA, [width] pixels square) straight into memory
@visibleForTesting
void debugAddDemTile(int x, int y, int z, ByteData data, int width) => _storeTile("$x,$y,$z", data, width);

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
  final bitPos = (((x % 1.0) * w).toInt() + (((y % 1.0) * w).toInt() * w).toInt()) * 4;
  final r = data.getUint8(bitPos + 0);
  final g = data.getUint8(bitPos + 1);
  final b = data.getUint8(bitPos + 2);
  return ((r * 256 + g + b.toDouble() / 256) - 32768);
}

/// Physically plausible ground elevation (meters). Lowest land is ~-430m (Dead Sea), highest ~8849m (Everest).
bool isValidElevation(double elev) => elev > -500 && elev < 9000;

String _address(Point3 point) => "${point.x.toInt()},${point.y.toInt()},${point.z.toInt()}";

double? _sampleTile(String pointAddress, Point3 point) {
  final elev = _sampleByteData(_tileCacheData[pointAddress]!, _tileCacheWidth[pointAddress]!, point.x, point.y);
  // Reject no-data / corrupt pixels (e.g. rgb 0,0,0 decodes to -32768m) and deep bathymetry.
  return isValidElevation(elev) ? elev : null;
}

/// Sample the DEM layer. (digital elevation map)
/// Returns elevation in Meters
double? sampleDem(LatLng latlng, bool highRes) => sampleDemAt(latlng, highRes ? demZoomLevels[1] : demZoomLevels[0]);

/// Sample the DEM layer from tiles at [zoom]. Returns elevation in Meters
///
/// While that tile loads, a loaded tile up to [fallbackLevels] zoom levels finer or coarser stands in.
double? sampleDemAt(LatLng latlng, int zoom, {int fallbackLevels = 0}) {
  final point = _unproject(latlng, zoom);
  final pointAddress = _address(point);

  // Check cache first
  if (_tileCacheData.containsKey(pointAddress)) {
    // Tiles in use stay in memory
    if (_tileCacheQueue.last != pointAddress) {
      _tileCacheQueue.remove(pointAddress);
      _tileCacheQueue.add(pointAddress);
    }
    return _sampleTile(pointAddress, point);
  } else {
    if (!_fetchQueue.contains(pointAddress)) {
      // Schedule this tile to be pulled
      _fetchQueue.add(pointAddress);
      _startFetching();
    }
  }

  for (int level = 1; level <= fallbackLevels; level++) {
    // Finer first: it's what's left over after zooming out
    for (final z in [zoom + level, zoom - level]) {
      if (z < 0) continue;
      final other = _unproject(latlng, z);
      final otherAddress = _address(other);
      if (_tileCacheData.containsKey(otherAddress)) return _sampleTile(otherAddress, other);
    }
  }

  // We didn't have it this time, try again when it's loaded.
  return null;
}
