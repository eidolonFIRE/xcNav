import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:xcnav/datadog.dart';

/// A raster tile service we fetch and cache ourselves (not through the map engine).
/// Coordinates are always XYZ (slippy map). [urlBuilder] handles any scheme quirks (eg. TMS).
class RasterTileSource {
  /// Also the cache folder name and the path segment on the local tile server
  final String name;
  final String Function(int z, int x, int y) urlBuilder;
  final int maxNativeZoom;

  /// Pixel size of the tile images
  final int tileSize;
  final String ext;
  final String contentType;

  /// Browse cache entries older than this are refreshed (kept as a fallback when offline)
  final Duration maxAge;

  /// Optional sub-folder for versioned sources, eg. the sectional chart cycle.
  final String? Function()? version;

  /// Called when the server says a tile doesn't exist
  final VoidCallback? onNotFound;

  const RasterTileSource({
    required this.name,
    required this.urlBuilder,
    required this.maxNativeZoom,
    this.tileSize = 256,
    required this.ext,
    required this.contentType,
    this.maxAge = const Duration(days: 16),
    this.version,
    this.onNotFound,
  });
}

/// Thrown when a tile couldn't be fetched for a reason that might fix itself (eg. no network).
class TileFetchException implements Exception {
  final String message;
  TileFetchException(this.message);
  @override
  String toString() => "TileFetchException: $message";
}

/// File based tile cache.
///
/// - Browse cache: `<cache>/tiles/<source>[/<version>]/<z>/<x>/<y>.<ext>`, refreshed after [RasterTileSource.maxAge].
/// - Offline areas: `<support>/offline_tiles/<areaId>/<source>/<z>/<x>/<y>.<ext>`, never purged.
class TileCache {
  final Map<String, RasterTileSource> sources = {};

  /// Offline area ids that hold tiles for each source
  final Map<String, Set<String>> offlineAreas = {};

  Directory? _browseDir;
  Directory? _offlineDir;
  final Map<String, Future<Uint8List?>> _inFlight = {};
  http.Client _client = http.Client();

  bool get isInit => _browseDir != null && _offlineDir != null;

  void register(RasterTileSource source) => sources[source.name] = source;

  Future init() async {
    try {
      _browseDir = Directory("${(await getApplicationCacheDirectory()).path}/tiles");
      _offlineDir = Directory("${(await getApplicationSupportDirectory()).path}/offline_tiles");
      await _browseDir!.create(recursive: true);
      await _offlineDir!.create(recursive: true);
    } catch (e, trace) {
      _browseDir = null;
      _offlineDir = null;
      error("Tile cache: init failed", errorMessage: e.toString(), errorStackTrace: trace);
    }
  }

  /// Override the network client (tests)
  @visibleForTesting
  set client(http.Client value) => _client = value;

  /// Point the cache at other folders (tests)
  @visibleForTesting
  void initAt(Directory browse, Directory offline) {
    _browseDir = browse;
    _offlineDir = offline;
  }

  String _browsePath(RasterTileSource src, int z, int x, int y) {
    final ver = src.version?.call();
    return "${_browseDir!.path}/${src.name}${ver != null ? "/$ver" : ""}/$z/$x/$y.${src.ext}";
  }

  String offlinePath(String areaId, RasterTileSource src, int z, int x, int y) =>
      "${_offlineDir!.path}/$areaId/${src.name}/$z/$x/$y.${src.ext}";

  Directory offlineAreaDir(String areaId) => Directory("${_offlineDir!.path}/$areaId");

  Future<Uint8List?> _readIfExists(String path, {Duration? maxAge}) async {
    final file = File(path);
    try {
      if (!await file.exists()) return null;
      if (maxAge != null && clock.now().difference(await file.lastModified()) > maxAge) return null;
      return await file.readAsBytes();
    } catch (e) {
      return null;
    }
  }

  static Future _writeAtomic(String path, Uint8List bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmp = File("$path.${DateTime.now().microsecondsSinceEpoch}.tmp");
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  /// Download a tile. Returns null if the server doesn't have it. Throws [TileFetchException] on network trouble.
  Future<Uint8List?> _fetch(RasterTileSource src, int z, int x, int y) async {
    final http.Response resp;
    try {
      resp = await _client
          .get(Uri.parse(src.urlBuilder(z, x, y)), headers: {"User-Agent": "xcNav"}).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw TileFetchException(e.toString());
    }
    if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) return resp.bodyBytes;
    if (resp.statusCode == 404 || resp.statusCode == 204) {
      src.onNotFound?.call();
      return null;
    }
    throw TileFetchException("HTTP ${resp.statusCode}");
  }

  /// Tile bytes from the browse cache, an offline area, or the network (in that order).
  /// Falls back to a stale cached copy when the network fails.
  Future<Uint8List?> getTile(RasterTileSource src, int z, int x, int y) {
    final key = "${src.name}/${src.version?.call()}/$z/$x/$y";
    // (Block body: returning the removed future from whenComplete would wait on itself)
    return _inFlight[key] ??= _getTile(src, z, x, y).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<Uint8List?> _getTile(RasterTileSource src, int z, int x, int y) async {
    if (!isInit) {
      try {
        return await _fetch(src, z, x, y);
      } on TileFetchException {
        return null;
      }
    }

    final browsePath = _browsePath(src, z, x, y);
    final fresh = await _readIfExists(browsePath, maxAge: src.maxAge);
    if (fresh != null) return fresh;

    for (final areaId in offlineAreas[src.name] ?? const <String>{}) {
      final bytes = await _readIfExists(offlinePath(areaId, src, z, x, y));
      if (bytes != null) return bytes;
    }

    try {
      final bytes = await _fetch(src, z, x, y);
      if (bytes != null) {
        try {
          await _writeAtomic(browsePath, bytes);
        } catch (e) {
          debugPrint("Tile cache: couldn't write $browsePath: $e");
        }
      }
      return bytes;
    } on TileFetchException {
      return await _readIfExists(browsePath);
    }
  }

  /// Make sure an offline area has this tile. Returns the bytes stored (0 if it was already there or doesn't exist).
  /// Throws [TileFetchException] on network trouble.
  Future<int> downloadTile(String areaId, RasterTileSource src, int z, int x, int y) async {
    final path = offlinePath(areaId, src, z, x, y);
    if (await File(path).exists()) return 0;
    final bytes = await _readIfExists(_browsePath(src, z, x, y), maxAge: src.maxAge) ?? await _fetch(src, z, x, y);
    if (bytes == null) return 0;
    await _writeAtomic(path, bytes);
    return bytes.length;
  }

  static Future<({int files, int bytes})> _dirStats(Directory dir) async {
    int files = 0;
    int bytes = 0;
    if (!await dir.exists()) return (files: 0, bytes: 0);
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        files++;
        bytes += await entity.length();
      }
    }
    return (files: files, bytes: bytes);
  }

  Future<({int files, int bytes})> browseStats() async =>
      isInit ? await _dirStats(_browseDir!) : (files: 0, bytes: 0);

  Future<({int files, int bytes})> areaStats(String areaId) async =>
      isInit ? await _dirStats(offlineAreaDir(areaId)) : (files: 0, bytes: 0);

  Future clearBrowseCache() async {
    if (!isInit) return;
    try {
      if (await _browseDir!.exists()) await _browseDir!.delete(recursive: true);
      await _browseDir!.create(recursive: true);
    } catch (e, trace) {
      error("Tile cache: clear failed", errorMessage: e.toString(), errorStackTrace: trace);
    }
  }

  Future deleteArea(String areaId) async {
    for (final each in offlineAreas.values) {
      each.remove(areaId);
    }
    if (!isInit) return;
    final dir = offlineAreaDir(areaId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future deleteAreaSource(String areaId, String sourceName) async {
    offlineAreas[sourceName]?.remove(areaId);
    if (!isInit) return;
    final dir = Directory("${offlineAreaDir(areaId).path}/$sourceName");
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Remove browse cache tiles that expired a while ago (they're only useful as an offline fallback).
  Future purge({Duration graceAfterExpiry = const Duration(days: 30)}) async {
    if (!isInit) return;
    final now = clock.now();
    for (final src in sources.values) {
      final dir = Directory("${_browseDir!.path}/${src.name}");
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File && now.difference(await entity.lastModified()) > src.maxAge + graceAfterExpiry) {
            await entity.delete();
          }
        }
      } catch (e) {
        debugPrint("Tile cache: purge ${src.name} failed: $e");
      }
    }
  }
}

final tileCache = TileCache();
