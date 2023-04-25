import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'package:dart_numerics/dart_numerics.dart' as math;

TileLayer? _demTileLayer;

// const demZoomLevel = 12;

// Digital Elevation Map - service

Future initDemCache() async {
  // init elevation map (dem = digital elevation map)
  final StoreDirectory demStore = FMTC.instance("dem");
  await demStore.manage.createAsync();
  await demStore.metadata
      .addAsync(key: 'sourceURL', value: 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png');
  await demStore.metadata.addAsync(
    key: 'validDuration',
    value: '14',
  );
  await demStore.metadata.addAsync(
    key: 'behaviour',
    value: 'cacheFirst',
  );

  // set the layer
  _demTileLayer = TileLayer(
    urlTemplate: 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png',
    tileProvider: FMTC.instance("dem").getTileProvider(
          FMTCTileProviderSettings(
            behavior: CacheBehavior.cacheFirst,
            cachedValidDuration: const Duration(days: 14),
          ),
        ),
    // maxNativeZoom: demZoomLevel.toDouble(),
    // minNativeZoom: demZoomLevel.toDouble(),
  );
}

Coords _unproject(LatLng latlng, int zoom) {
  final double n = pow(2.0, zoom.toDouble()).toDouble();
  final xtile = n * ((latlng.longitude + 180) / 360);
  final ytile = n * (1 - math.asinh(tan(latlng.latitude / 180 * pi)) / pi) / 2;
  return Coords(xtile, ytile)..z = zoom;
}

/// Sample the DEM layer. (digital elevation map)
/// Returns elevation in Meters
Future<double?> sampleDem(LatLng latlng, bool highRes, {double offset = 0}) {
  // early out
  if (_demTileLayer == null) {
    return Future.value(null);
  }

  Completer<double?> completer = Completer();
  final point = _unproject(latlng, highRes ? 12 : 10);
  final pointInt = Coords(point.x.toInt(), point.y.toInt())..z = point.z.toInt();
  final img = _demTileLayer!.tileProvider.getImage(pointInt, _demTileLayer!);

  final imgStream = img.resolve(ImageConfiguration.empty);
  imgStream.addListener(ImageStreamListener((imgInfo, state) {
    // debugPrint("$state ${imgInfo.toString()}");
    if (!state) {
      // TODO: re-cache this
      imgInfo.image.toByteData().then((value) {
        if (value != null) {
          int s = imgInfo.image.width;
          int x = ((point.x % 1) * s).toInt();
          int y = ((point.y % 1) * s).toInt();
          // debugPrint("offset: $x, $y ( ${(x + y * s) * 4} / ${imgInfo.sizeBytes} )");
          final bitPos = (x + y * s) * 4;
          final r = value.getUint8(bitPos + 0);
          final g = value.getUint8(bitPos + 1);
          final b = value.getUint8(bitPos + 2);
          // final a = value.getUint8(bitPos + 3);
          // debugPrint("rgba : $r $g $b $a");
          final elev = ((r * 256 + g + b.toDouble() / 256) - 32768);
          // debugPrint("Elevation: ${elev} meters");

          // TODO: do more testing with lagging elevation data
          // Timer(Duration(seconds: 10), () => {completer.complete(elev + offset)});
          completer.complete(elev + offset);
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
