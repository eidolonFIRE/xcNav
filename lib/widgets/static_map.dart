import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/models/map_shapes.dart';
import 'package:xcnav/services/tile_cache.dart';
import 'package:xcnav/views/map/xc_map.dart';

/// Non-interactive map preview drawn entirely in Flutter, from cached raster tiles.
///
/// Much lighter than a native map, so it's what lists of cards use. Overlay [children] (eg. `MarkerLayer`)
/// work the same as on an `XcMap`.
class StaticMap extends StatelessWidget {
  final MapTileSrc tileSrc;
  final LatLngBounds bounds;
  final EdgeInsets padding;
  final double maxZoom;
  final List<ShapeLayer> shapes;
  final List<Widget> children;

  const StaticMap({
    super.key,
    this.tileSrc = MapTileSrc.topo,
    required this.bounds,
    this.padding = const EdgeInsets.all(10),
    this.maxZoom = 15,
    this.shapes = const [],
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final camera = MapCamera.fit(bounds, constraints.biggest, padding: padding, maxZoom: maxZoom);
      return ClipRect(
        child: XcMapScope(
          controller: XcMapController.fixed(camera),
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0xffe8ebe4)),
            RasterTileGrid(source: previewTilesFor(tileSrc), camera: camera),
            CustomPaint(painter: ShapePainter(camera, shapes)),
            ...children,
          ]),
        ),
      );
    });
  }
}

/// Raster tiles covering a (north-up, untilted) camera view
class RasterTileGrid extends StatelessWidget {
  final RasterTileSource source;
  final MapCamera camera;

  const RasterTileGrid({super.key, required this.source, required this.camera});

  @override
  Widget build(BuildContext context) {
    // Tile zoom whose pixels best match the screen
    final zoomOffset = log(mapWorldTileSize / source.tileSize) / ln2;
    final tileZoom = (camera.zoom + zoomOffset).round().clamp(0, source.maxNativeZoom);
    final tileCount = 1 << tileZoom;
    final ws = camera.worldSize;
    final tilePx = ws / tileCount;
    final origin = projectMercator(camera.center, worldSize: ws) - camera.size.center(Offset.zero);

    final minX = (origin.dx / tilePx).floor();
    final maxX = ((origin.dx + camera.size.width) / tilePx).floor();
    final minY = max(0, (origin.dy / tilePx).floor());
    final maxY = min(tileCount - 1, ((origin.dy + camera.size.height) / tilePx).floor());

    final List<Widget> tiles = [];
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        tiles.add(Positioned(
          left: x * tilePx - origin.dx,
          top: y * tilePx - origin.dy,
          // Overlap a hair so seams don't show
          width: tilePx + 0.5,
          height: tilePx + 0.5,
          child: _TileImage(source: source, z: tileZoom, x: x % tileCount, y: y),
        ));
      }
    }
    return Stack(children: tiles);
  }
}

class _TileImage extends StatefulWidget {
  final RasterTileSource source;
  final int z;
  final int x;
  final int y;

  const _TileImage({required this.source, required this.z, required this.x, required this.y});

  @override
  State<_TileImage> createState() => _TileImageState();
}

class _TileImageState extends State<_TileImage> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = tileCache.getTile(widget.source, widget.z, widget.x, widget.y);
  }

  @override
  void didUpdateWidget(covariant _TileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.z != widget.z ||
        oldWidget.x != widget.x ||
        oldWidget.y != widget.y) {
      _bytes = tileCache.getTile(widget.source, widget.z, widget.x, widget.y);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snapshot) => snapshot.data == null
            ? const SizedBox()
            : Image.memory(snapshot.data!, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium));
  }
}

/// Paints [ShapeLayer]s the way the native map draws them.
class ShapePainter extends CustomPainter {
  final MapCamera camera;
  final List<ShapeLayer> layers;

  ShapePainter(this.camera, this.layers);

  Path _path(List<Offset?> points, {bool close = false}) {
    final path = Path();
    bool started = false;
    for (final p in points) {
      if (p == null) continue;
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (close) path.close();
    return path;
  }

  void _strokePath(Canvas canvas, Path path, Color color, double width, LinePattern pattern) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = pattern == LinePattern.dashed ? StrokeCap.butt : StrokeCap.round;
    if (pattern == LinePattern.solid) {
      canvas.drawPath(path, paint);
      return;
    }
    final dash = lineDashArrays[pattern]!.map((e) => e * width).toList();
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      int i = 0;
      while (distance < metric.length) {
        final len = dash[i % dash.length];
        if (i.isEven) {
          if (len == 0) {
            final tangent = metric.getTangentForOffset(distance);
            if (tangent != null) {
              canvas.drawCircle(tangent.position, width / 2, Paint()..color = color);
            }
          } else {
            canvas.drawPath(metric.extractPath(distance, min(metric.length, distance + len)), paint);
          }
        }
        distance += len;
        i++;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final layer in layers) {
      for (final polygon in layer.polygons) {
        final path = _path(polygon.points.map(camera.latLngToScreen).toList(), close: true);
        canvas.drawPath(path, Paint()..color = polygon.fillColor);
        if (polygon.borderColor != null && polygon.borderWidth > 0) {
          _strokePath(canvas, path, polygon.borderColor!, polygon.borderWidth, polygon.borderPattern);
        }
      }
      for (final line in layer.lines) {
        final path = _path(line.points.map(camera.latLngToScreen).toList());
        if (line.borderColor != null && line.borderWidth > 0) {
          _strokePath(canvas, path, line.borderColor!, line.width + 2 * line.borderWidth, LinePattern.solid);
        }
        _strokePath(canvas, path, line.color, line.width, line.pattern);
      }
    }
  }

  @override
  bool shouldRepaint(ShapePainter oldDelegate) => oldDelegate.camera != camera || !identical(oldDelegate.layers, layers);
}
