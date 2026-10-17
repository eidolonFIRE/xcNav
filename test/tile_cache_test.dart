import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:xcnav/services/tile_cache.dart';

void main() {
  late Directory tmp;
  late TileCache cache;
  late int requests;
  late int status;
  late bool offline;
  late int notFound;
  String? version;
  final tile = Uint8List.fromList([1, 2, 3, 4]);

  late RasterTileSource src;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp("tile_cache_test");
    requests = 0;
    status = 200;
    offline = false;
    notFound = 0;
    version = null;
    src = RasterTileSource(
      name: "test",
      urlBuilder: (z, x, y) => "https://tiles.example.com/$z/$x/$y.png",
      maxNativeZoom: 12,
      ext: "png",
      contentType: "image/png",
      maxAge: const Duration(days: 1),
      version: () => version,
      onNotFound: () => notFound++,
    );
    cache = TileCache()
      ..initAt(Directory("${tmp.path}/browse"), Directory("${tmp.path}/offline"))
      ..register(src)
      ..client = MockClient((request) async {
        requests++;
        if (offline) throw const SocketException("offline");
        return http.Response.bytes(status == 200 ? tile : [], status);
      });
  });

  tearDown(() => tmp.delete(recursive: true));

  test("fetches once, then serves from the browse cache", () async {
    expect(await cache.getTile(src, 5, 1, 2), tile);
    expect(await cache.getTile(src, 5, 1, 2), tile);
    expect(requests, 1);
  });

  test("simultaneous requests share one fetch", () async {
    final results = await Future.wait([cache.getTile(src, 5, 1, 2), cache.getTile(src, 5, 1, 2)]);
    expect(results, [tile, tile]);
    expect(requests, 1);
  });

  test("offline area tiles are used without the network", () async {
    final path = cache.offlinePath("area1", src, 7, 3, 4);
    await File(path).create(recursive: true);
    await File(path).writeAsBytes([9, 9]);
    cache.offlineAreas["test"] = {"area1"};

    expect(await cache.getTile(src, 7, 3, 4), [9, 9]);
    expect(requests, 0);
  });

  test("falls back to an expired copy when the network is down", () async {
    await cache.getTile(src, 5, 1, 2);
    final files = (await Directory("${tmp.path}/browse").list(recursive: true).toList()).whereType<File>().toList();
    expect(files.length, 1);
    await files.first.setLastModified(DateTime.now().subtract(const Duration(days: 3)));

    offline = true;
    expect(await cache.getTile(src, 5, 1, 2), tile);
    expect(requests, 2, reason: "expired, so it tried the network first");
  });

  test("missing tiles", () async {
    status = 404;
    expect(await cache.getTile(src, 5, 1, 2), isNull);
    expect(notFound, 1);
  });

  test("versioned sources cache per version", () async {
    version = "20260806";
    await cache.getTile(src, 5, 1, 2);
    version = "20261001";
    await cache.getTile(src, 5, 1, 2);
    expect(requests, 2);
    expect(await Directory("${tmp.path}/browse/test/20260806").exists(), true);
  });

  test("downloadTile stores into the area once", () async {
    expect(await cache.downloadTile("area1", src, 6, 1, 1), tile.length);
    expect(await File(cache.offlinePath("area1", src, 6, 1, 1)).readAsBytes(), tile);
    expect(await cache.downloadTile("area1", src, 6, 1, 1), 0);
    expect(requests, 1);
  });

  test("downloadTile reports network trouble", () async {
    offline = true;
    expect(() => cache.downloadTile("area1", src, 6, 1, 1), throwsA(isA<TileFetchException>()));
  });

  test("stats, clearing, deleting", () async {
    await cache.getTile(src, 5, 1, 2);
    await cache.downloadTile("area1", src, 6, 1, 1);
    cache.offlineAreas["test"] = {"area1"};

    expect((await cache.browseStats()).files, 1);
    expect((await cache.areaStats("area1")).bytes, tile.length);

    await cache.clearBrowseCache();
    expect((await cache.browseStats()).files, 0);

    await cache.deleteArea("area1");
    expect((await cache.areaStats("area1")).files, 0);
    expect(cache.offlineAreas["test"], isEmpty);
  });

  test("purge drops long expired tiles", () async {
    await cache.getTile(src, 5, 1, 2);
    await cache.getTile(src, 5, 1, 3);
    final files = (await Directory("${tmp.path}/browse").list(recursive: true).toList()).whereType<File>().toList();
    await files.first.setLastModified(DateTime.now().subtract(const Duration(days: 60)));

    await cache.purge();
    expect((await cache.browseStats()).files, 1);
  });
}
