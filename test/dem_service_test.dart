import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/dem_service.dart';
import 'package:xcnav/models/map_camera.dart';

/// Terrarium encoded tile, all at one [elevation]
ByteData demTile(double elevation, {int width = 4}) {
  final value = elevation + 32768;
  final r = value ~/ 256;
  final g = value.floor() - r * 256;
  final b = ((value - value.floor()) * 256).round();
  final data = ByteData(width * width * 4);
  for (int i = 0; i < width * width; i++) {
    data
      ..setUint8(i * 4, r)
      ..setUint8(i * 4 + 1, g)
      ..setUint8(i * 4 + 2, b)
      ..setUint8(i * 4 + 3, 255);
  }
  return data;
}

void main() {
  void addTile(LatLng point, int z, double elevation) {
    final (x, y) = tileXY(point, z);
    debugAddDemTile(x.floor(), y.floor(), z, demTile(elevation), 4);
  }

  test("reads loaded tiles", () {
    const point = LatLng(37.5, -122.3);
    final loaded = demTilesLoaded.value;
    expect(sampleDemAt(point, 10), isNull, reason: "not loaded yet");
    addTile(point, 10, 1000.5);
    expect(demTilesLoaded.value, loaded + 1);
    expect(sampleDemAt(point, 10), 1000.5);
    expect(sampleDem(point, false), 1000.5, reason: "low res is zoom 10");
  });

  test("nearby zoom levels stand in while a tile loads", () {
    const point = LatLng(40, -105);
    addTile(point, 8, 1500);
    expect(sampleDemAt(point, 9), isNull);
    expect(sampleDemAt(point, 9, fallbackLevels: 1), 1500);
    addTile(point, 10, 1600);
    expect(sampleDemAt(point, 9, fallbackLevels: 1), 1600, reason: "finer first");
    expect(sampleDemAt(point, 12, fallbackLevels: 1), isNull, reason: "too many levels away");
  });

  test("least recently used tiles go first", () {
    const z = 10;
    LatLng tileCenter(int x) => unprojectMercator(Offset(x + 0.5, 400.5), worldSize: (1 << z).toDouble());
    // Fill the cache
    for (int x = 0; x < 30; x++) {
      debugAddDemTile(x, 400, z, demTile(x.toDouble()), 4);
    }
    // Use the oldest one, then make room for another
    expect(sampleDemAt(tileCenter(0), z), 0);
    debugAddDemTile(30, 400, z, demTile(30), 4);
    expect(sampleDemAt(tileCenter(0), z), 0, reason: "just used");
    expect(sampleDemAt(tileCenter(1), z), isNull, reason: "oldest unused");
    expect(sampleDemAt(tileCenter(2), z), 2);
    expect(sampleDemAt(tileCenter(30), z), 30);
  });
}
