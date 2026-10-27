import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/models/glide_range.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/services/glide_range_service.dart';
import 'package:xcnav/settings_service.dart';

/// Cells from the edge of the reachable area to where the fill has faded to fully transparent.
const double _fadeCells = 6;

const _lowColor = Colors.pink;
const _highColor = Colors.yellow;
const _unknownColor = Color(0xff9e9e9e);
const int _fillAlpha = 200;
const int _edgeAlpha = 220;
const int _unknownAlpha = 60;

/// Neighbors already visited when scanning rows top to bottom, each left to right, with their distance in cells.
/// Includes knight steps so the distance is within ~2% of straight-line in any direction.
final List<(int, int, double)> _chamferForward = [
  (-1, 0, 1), (0, -1, 1), (-1, -1, sqrt2), (-1, 1, sqrt2), //
  (-2, -1, sqrt(5)), (-2, 1, sqrt(5)), (-1, -2, sqrt(5)), (-1, 2, sqrt(5)),
];

/// Cells from each reachable cell to the nearest cell outside the reachable area (or off the grid). 0 where
/// unreachable, 1 on the edge.
Float32List glideEdgeDistance(GlideRange range) {
  final n = range.grid.size;
  final dist = Float32List(n * n);
  for (int i = 0; i < n * n; i++) {
    dist[i] = range.excess[i].isNaN ? 0 : double.infinity;
  }

  /// Shortest distance via the neighbors at [sign] times the forward offsets. Off the grid counts as unreachable.
  void relax(int row, int col, int sign) {
    final i = row * n + col;
    if (dist[i] == 0) return;
    double d = dist[i];
    for (final (dr, dc, step) in _chamferForward) {
      final r = row + sign * dr;
      final c = col + sign * dc;
      final neighbor = r < 0 || r >= n || c < 0 || c >= n ? 0.0 : dist[r * n + c];
      d = min(d, neighbor + step);
    }
    dist[i] = d;
  }

  // Two-pass chamfer: down from the top-left, then back up from the bottom-right
  for (int row = 0; row < n; row++) {
    for (int col = 0; col < n; col++) {
      relax(row, col, 1);
    }
  }
  for (int row = n - 1; row >= 0; row--) {
    for (int col = n - 1; col >= 0; col--) {
      relax(row, col, -1);
    }
  }
  return dist;
}

/// RGBA pixels, one per grid cell. Row 0 is north.
///
/// Reachable cells shade from [_lowColor] at the edge of the reachable area toward [_highColor], fading out to fully
/// transparent [_fadeCells] in from the edge so the map shows through the middle. The fade goes by cell count only,
/// so it's the same width all the way around. Cells on the edge are drawn darker so the boundary reads clearly.
/// Cells the glide couldn't check yet are grey.
Uint8List glideRangePixels(GlideRange range) {
  final n = range.grid.size;
  final dist = glideEdgeDistance(range);
  final pixels = Uint8List(n * n * 4);
  for (int i = 0; i < n * n; i++) {
    final d = dist[i];
    Color? color;
    int alpha = 0;
    if (d > 0) {
      final t = min(1.0, (d - 1) / _fadeCells);
      color = Color.lerp(_lowColor, _highColor, t);
      alpha = d <= 1 ? _edgeAlpha : (_fillAlpha * (1 - t)).round();
    } else if (range.unknown[i] == 1) {
      color = _unknownColor;
      alpha = _unknownAlpha;
    }
    if (color != null && alpha > 0) {
      // Raw pixels are premultiplied. Unscaled color would brighten the map even where alpha is 0.
      pixels[i * 4] = (color.r * alpha).round();
      pixels[i * 4 + 1] = (color.g * alpha).round();
      pixels[i * 4 + 2] = (color.b * alpha).round();
      pixels[i * 4 + 3] = alpha;
    }
  }
  return pixels;
}

/// Shaded area the pilot can glide to.
class GlideRangeLayer extends StatefulWidget {
  const GlideRangeLayer({super.key});

  @override
  State<GlideRangeLayer> createState() => _GlideRangeLayerState();
}

class _GlideRangeLayerState extends State<GlideRangeLayer> {
  ui.Image? image;
  LatLngBounds? bounds;

  @override
  void initState() {
    super.initState();
    myTelemetry.addListener(onTelemetry);
    glideRangeService.range.addListener(onRange);
    onTelemetry();
    if (glideRangeService.range.value != null) onRange();
  }

  @override
  void dispose() {
    myTelemetry.removeListener(onTelemetry);
    glideRangeService.range.removeListener(onRange);
    glideRangeService.clear();
    image?.dispose();
    super.dispose();
  }

  void onTelemetry() {
    glideRangeService.update(myTelemetry.geo,
        vario: myTelemetry.varioSmooth.value,
        speed: myTelemetry.speedSmooth.value,
        wind: Provider.of<Wind>(context, listen: false).result,
        mode: settingsMgr.glideRangeMode.value,
        defaultRatio: settingsMgr.glideRangeDefaultRatio.value,
        margin: settingsMgr.glideRangeMargin.value);
  }

  void onRange() {
    final range = glideRangeService.range.value;
    if (range == null) {
      setImage(null, null);
      return;
    }
    final n = range.grid.size;
    ui.decodeImageFromPixels(glideRangePixels(range), n, n, ui.PixelFormat.rgba8888, (decoded) {
      // Range may have changed while decoding
      if (!mounted || glideRangeService.range.value != range) {
        decoded.dispose();
        return;
      }
      setImage(decoded, range.grid.bounds);
    });
  }

  void setImage(ui.Image? newImage, LatLngBounds? newBounds) {
    if (!mounted) {
      newImage?.dispose();
      return;
    }
    final old = image;
    setState(() {
      image = newImage;
      bounds = newBounds;
    });
    old?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (image == null || bounds == null) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    final rect = Rect.fromPoints(
      camera.getOffsetFromOrigin(bounds!.northWest),
      camera.getOffsetFromOrigin(bounds!.southEast),
    );
    return MobileLayerTransformer(
      child: ClipRect(
        child: Stack(children: [
          Positioned.fromRect(
            rect: rect,
            child: RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.low),
          ),
        ]),
      ),
    );
  }
}
