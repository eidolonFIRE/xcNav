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
              stores: {"dem": BrowseStoreStrategy.readUpdateCreate}, cachedValidDuration: const Duration(days: 60)));
    } else {
      error("DEM store not ready!");
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

final Queue<String> _tileCacheQueue = Queue();
final Map<String, ByteData> _tileCacheData = {};
final Map<String, int> _tileCacheWidth = {};

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
Future<double?> sampleDem(LatLng latlng, bool highRes) {
  // early out
  if (_demTileLayer == null) {
    return Future.value(null);
  }

  final point = _unproject(latlng, highRes ? 12 : 10);
  final pointTile = TileCoordinates(point.x.toInt(), point.y.toInt(), point.z.toInt());
  final pointAddress = "${pointTile.x},${pointTile.y},${pointTile.z}";

  // Check cache first
  if (_tileCacheData.containsKey(pointAddress)) {
    return Future.value(
        _sampleByteData(_tileCacheData[pointAddress]!, _tileCacheWidth[pointAddress]!, point.x, point.y));
  }

  // Query the image
  Completer<double?> completer = Completer();
  final img = _demTileLayer!.tileProvider.getImage(pointTile, _demTileLayer!);
  // debugPrint("Fetch pointTile(${pointTile.x}, ${pointTile.y}, ${pointTile.z})");
  final imgStream = img.resolve(ImageConfiguration.empty);
  imgStream.addListener(ImageStreamListener((imgInfo, state) {
    // debugPrint("$state ${imgInfo.toString()}");
    if (!state) {
      imgInfo.image.toByteData().then((data) {
        if (data != null) {
          final w = imgInfo.image.width;
          // debugPrint("Elevation: $elev meters");
          final elev = _sampleByteData(data, w, point.x, point.y);
          // Note: use this line to test lag
          // Timer(Duration(seconds: 10), () => {completer.complete(elev + offset)});

          completer.complete(elev);

          // store back to cache
          _tileCacheWidth[pointAddress] = w;
          _tileCacheQueue.add(pointAddress);
          _tileCacheData[pointAddress] = data;

          // clean cache
          if (_tileCacheQueue.length > 10) {
            final oldest = _tileCacheQueue.first;
            _tileCacheQueue.removeFirst();
            _tileCacheData.remove(oldest);
            _tileCacheWidth.remove(oldest);
          }
        } else {
          completer.complete(null);
        }
      }).onError((error, stackTrace) {
        completer.complete(null);
      });
    } else {
      // Didn't work...
      completer.complete(null);
    }
  }));
  return completer.future;
}
