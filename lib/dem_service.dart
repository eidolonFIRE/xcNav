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

/// Tile addresses to be fetched.
final Queue<String> _fetchQueue = Queue();

final Queue<String> _tileCacheQueue = Queue();
final Map<String, ByteData> _tileCacheData = {};
final Map<String, int> _tileCacheWidth = {};

// Digital Elevation Map - service
Future initDemCache() async {
  // init elevation map (dem = digital elevation map)
  const demStore = FMTCStore("dem");
  await demStore.manage.create();
  await demStore.metadata
      .set(key: 'sourceURL', value: 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png');

  // set the layer
  demStore.manage.ready.then((ready) {
    if (ready) {
      _demTileLayer = TileLayer(
          urlTemplate: 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png',
          tileProvider: FMTCTileProvider(
              stores: {"dem": BrowseStoreStrategy.readUpdateCreate}, cachedValidDuration: const Duration(days: 90)));
    } else {
      error("DEM store not ready!");
    }
  });

  // Fetch timer
  Timer.periodic(Duration(milliseconds: 100), (timer) {
    // Pop one off queue and fetch it

    final pointAddress = _fetchQueue.firstOrNull;
    if (pointAddress == null) {
      return;
    }

    if (!_tileCacheQueue.contains(pointAddress)) {
      if (_demTileLayer == null) {
        // (DEBUG) debugPrint("Broken _demTileLayer");
        return;
      }

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
              }

              // clean cache
              if (_tileCacheQueue.length > 30) {
                final oldest = _tileCacheQueue.first;
                // (DEBUG) debugPrint("Popping one from DEM cache. $oldest");
                _tileCacheQueue.removeFirst();
                _tileCacheData.remove(oldest);
                _tileCacheWidth.remove(oldest);
              }

              // Good fetch!
              if (_fetchQueue.isNotEmpty) {
                _fetchQueue.removeFirst();
              }
            }
          });
        }
      }));
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

/// Sample the DEM layer. (digital elevation map)
/// Returns elevation in Meters
double? sampleDem(LatLng latlng, bool highRes) {
  final point = _unproject(latlng, highRes ? 12 : 10);
  final pointTile = TileCoordinates(point.x.toInt(), point.y.toInt(), point.z.toInt());
  final pointAddress = "${pointTile.x},${pointTile.y},${pointTile.z}";

  // Check cache first
  if (_tileCacheData.containsKey(pointAddress)) {
    return _sampleByteData(_tileCacheData[pointAddress]!, _tileCacheWidth[pointAddress]!, point.x, point.y);
  } else {
    if (!_fetchQueue.contains(pointAddress)) {
      // Schedule this tile to be pulled
      // (DEBUG) debugPrint("Queue fetch tile: $pointAddress");
      _fetchQueue.add(pointAddress);
    } else {
      // (DEBUG) debugPrint("Already queued for fetch: $pointAddress");
    }
  }

  // We didn't have it this time, try again when it's loaded.
  return null;
}
