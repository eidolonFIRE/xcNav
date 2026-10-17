import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:xcnav/datadog.dart';
import 'package:xcnav/services/tile_cache.dart';

/// Serves [tileCache] tiles to MapLibre over loopback HTTP.
///
/// MapLibre can only download offline regions described by a hosted style, and our sectional charts have none.
/// Routing those tiles through here lets one Dart cache handle browsing, offline areas, and chart cycle changes.
class LocalTileServer {
  /// A fixed port keeps tile URLs (and MapLibre's own cache of them) stable between launches.
  static const preferredPort = 47621;

  HttpServer? _server;
  Future? _starting;

  int? get port => _server?.port;

  Future ensureRunning() {
    if (_server != null) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future _start() async {
    try {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, preferredPort);
      } on SocketException {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      }
      debugPrint("Local tile server on port ${_server!.port}");
      final server = _server!;
      server.listen(_handle, onError: (e) {
        debugPrint("Local tile server error: $e");
        if (identical(_server, server)) _server = null;
      }, onDone: () {
        if (identical(_server, server)) _server = null;
      });
    } catch (e, trace) {
      error("Local tile server failed to start", errorMessage: e.toString(), errorStackTrace: trace);
    }
  }

  /// URL template for MapLibre (`{z}/{x}/{y}`, XYZ scheme)
  String tileUrl(String sourceName) =>
      "http://127.0.0.1:${port ?? preferredPort}/tiles/$sourceName/{z}/{x}/{y}";

  Future _handle(HttpRequest req) async {
    final response = req.response;
    try {
      final seg = req.uri.pathSegments;
      final src = seg.length == 5 && seg[0] == "tiles" ? tileCache.sources[seg[1]] : null;
      final z = seg.length == 5 ? int.tryParse(seg[2]) : null;
      final x = seg.length == 5 ? int.tryParse(seg[3]) : null;
      final y = seg.length == 5 ? int.tryParse(seg[4]) : null;
      final bytes = (src != null && z != null && x != null && y != null) ? await tileCache.getTile(src, z, x, y) : null;

      // Our cache is the source of truth. Have MapLibre ask again rather than keep its own copy.
      response.headers.set(HttpHeaders.cacheControlHeader, "no-cache");
      if (bytes == null) {
        response.statusCode = HttpStatus.notFound;
      } else {
        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.parse(src!.contentType);
        response.contentLength = bytes.length;
        response.add(bytes);
      }
    } catch (e) {
      debugPrint("Local tile server: ${req.uri}: $e");
      response.statusCode = HttpStatus.internalServerError;
    }
    await response.close();
  }

  Future stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}

final localTileServer = LocalTileServer();
