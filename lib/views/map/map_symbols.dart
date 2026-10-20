import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/views/map/map_markers.dart';

/// A marker drawn by the map itself, so it moves in step with the map. (Flutter markers over the map trail it by a
/// frame or two while panning.)
///
/// [child] is drawn into a picture once, and the picture is shared by every symbol with the same [imageKey].
/// It's only a picture: gestures inside [child] do nothing, use [onTap] / [onLongPress].
class MapSymbol {
  /// Unique within its layer
  final String id;
  final LatLng point;

  /// Size of [child] (logical pixels)
  final double width;
  final double height;

  /// Where [child] sits relative to [point], as for [MapMarker.alignment]
  final Alignment alignment;

  /// Room around [child]'s box for anything it draws outside of it (eg. labels)
  final EdgeInsets overflow;

  /// Names the picture. Symbols that look the same share a key, and one image.
  final String imageKey;
  final Widget child;

  /// Images in [child] to load before drawing it (eg. avatars). Bundled svg and png assets are loaded already.
  final List<ImageProvider> precache;

  /// Degrees clockwise. From north when the layer rotates with the map, from up on the screen otherwise.
  final double rotation;
  final double opacity;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MapSymbol({
    required this.id,
    required this.point,
    required this.width,
    required this.height,
    this.alignment = Alignment.center,
    this.overflow = EdgeInsets.zero,
    required this.imageKey,
    required this.child,
    this.precache = const [],
    this.rotation = 0,
    this.opacity = 1,
    this.onTap,
    this.onLongPress,
  });

  /// Where [point] is in [child]'s box, from its top left
  Offset get anchor => Offset(width * (1 - alignment.x) / 2, height * (1 - alignment.y) / 2);

  /// Flutter version, for where there's no map engine (widget tests)
  MapMarker toMarker(String layerId, {required bool rotateWithMap}) => MapMarker(
        key: ValueKey("${layerId}_$id"),
        point: point,
        width: width,
        height: height,
        alignment: alignment,
        rotateWithMap: rotateWithMap,
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: rotation * pi / 180,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onLongPress: onLongPress,
              child: IgnorePointer(child: child),
            ),
          ),
        ),
      );
}

/// [symbols] drawn by the map as one layer.
class SymbolLayer {
  final String id;
  final List<MapSymbol> symbols;

  /// [MapSymbol.rotation] turns with the map (eg. headings), and symbols lie flat on the map when it's tilted.
  /// Otherwise symbols stay upright on the screen.
  final bool rotateWithMap;

  /// Hidden when zoomed out further than this
  final double? minZoom;

  const SymbolLayer(this.id, {this.symbols = const [], this.rotateWithMap = false, this.minZoom});

  /// GeoJSON for the map: the symbols whose picture is in [images] (by image key)
  Map<String, dynamic> toGeoJson(Map<String, SymbolImage> images) => {
        "type": "FeatureCollection",
        "features": [
          for (final symbol in symbols)
            if (images[symbol.imageKey] case final image?)
              {
                "type": "Feature",
                "geometry": {
                  "type": "Point",
                  "coordinates": [symbol.point.longitude, symbol.point.latitude],
                },
                "properties": {
                  "id": symbol.id,
                  "image": image.id,
                  "rotate": symbol.rotation,
                  "offset": [image.offset.dx, image.offset.dy],
                  "opacity": symbol.opacity,
                  "tap": symbol.onTap != null,
                  "longTap": symbol.onLongPress != null,
                },
              }
        ],
      };

  MapSymbol? byId(Object? id) => symbols.where((e) => e.id == id).firstOrNull;
}

/// A symbol's picture, ready for the map
class SymbolImage {
  /// Style image id
  final String id;

  /// Pixels
  final int width;
  final int height;

  /// Premultiplied RGBA
  final Uint8List pixels;
  final double pixelRatio;

  /// From the symbol's point to the middle of the picture (logical pixels). The map's `icon-offset`.
  final Offset offset;

  const SymbolImage(
      {required this.id,
      required this.width,
      required this.height,
      required this.pixels,
      required this.pixelRatio,
      required this.offset});
}

/// Bundled pictures that map symbols use. Loaded once up front, so symbols draw them straight away.
const symbolSvgAssets = [
  "assets/images/pin.svg",
  "assets/images/path.svg",
  "assets/images/icon_windsock.svg",
  "assets/images/icon_camp.svg",
  "assets/images/chevron.svg",
  "assets/images/simple_arrow.svg",
  "assets/images/pilot_direction_arrow.svg",
  "assets/images/ga_small.svg",
  "assets/images/ga_heli.svg",
  "assets/images/ga_large.svg",
];
const symbolPngAssets = ["assets/images/red_arrow.png", "assets/images/default_avatar.png"];

/// Draws symbol pictures. Shared by every map, and keeps the ones used lately.
class SymbolImages {
  SymbolImages._();

  static final instance = SymbolImages._();

  /// Cached pictures, up to this many bytes
  static const _cacheBytes = 32 << 20;

  /// Pictures drawn at the same time
  static const _maxDrawing = 6;

  /// Most recently used last
  final LinkedHashMap<String, SymbolImage> _cache = LinkedHashMap();
  int _bytes = 0;
  final Map<String, Future<SymbolImage?>> _drawing = {};
  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue();
  Future<void>? _assets;

  static String _cacheId(String imageKey, double pixelRatio) => "$imageKey@${pixelRatio.toStringAsFixed(2)}";

  /// [symbol]'s picture at [pixelRatio]. [wrap] gives [MapSymbol.child] what it'd have in the app (theme etc).
  /// Null if there's nothing to see.
  Future<SymbolImage?> get(MapSymbol symbol, double pixelRatio, Widget Function(Widget child) wrap) {
    final id = _cacheId(symbol.imageKey, pixelRatio);
    final cached = _cache.remove(id);
    if (cached != null) {
      _cache[id] = cached;
      return SynchronousFuture(cached);
    }
    // Block body: returning the removed future from whenComplete would wait on itself
    return _drawing[id] ??= _draw(id, symbol, pixelRatio, wrap).whenComplete(() {
      _drawing.remove(id);
    });
  }

  Future<SymbolImage?> _draw(String id, MapSymbol symbol, double pixelRatio, Widget Function(Widget child) wrap) async {
    await (_assets ??= _loadAssets(pixelRatio));
    if (_running >= _maxDrawing) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      await Future.wait(symbol.precache.map((e) => _loadImage(e, pixelRatio)));
      final image = await drawSymbol(symbol, pixelRatio, wrap, id: id);
      if (image != null) _remember(id, image);
      return image;
    } catch (e, trace) {
      debugPrint("Map symbol ${symbol.imageKey} failed: $e\n$trace");
      return null;
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }

  void _remember(String id, SymbolImage image) {
    _cache[id] = image;
    _bytes += image.pixels.length;
    while (_bytes > _cacheBytes && _cache.length > 1) {
      final oldest = _cache.keys.first;
      _bytes -= _cache.remove(oldest)!.pixels.length;
    }
  }

  static Future<void> _loadAssets(double pixelRatio) => Future.wait([
        for (final path in symbolSvgAssets)
          SvgAssetLoader(path).loadBytes(null).then<void>((_) {}, onError: (e) => debugPrint("Map symbol $path: $e")),
        for (final path in symbolPngAssets) _loadImage(AssetImage(path), pixelRatio),
      ]);
}

/// Into the image cache, so widgets showing it have it straight away
Future<void> _loadImage(ImageProvider provider, double pixelRatio) {
  final done = Completer<void>();
  final stream = provider.resolve(ImageConfiguration(bundle: rootBundle, devicePixelRatio: pixelRatio));
  late final ImageStreamListener listener;
  void finish() {
    if (!done.isCompleted) done.complete();
    // Removed after this callback, not during it
    scheduleMicrotask(() => stream.removeListener(listener));
  }

  listener = ImageStreamListener((_, __) => finish(), onError: (_, __) => finish());
  stream.addListener(listener);
  return done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
}

/// Draws [symbol]'s picture (cropped to what's visible). Null if there's nothing to see.
Future<SymbolImage?> drawSymbol(MapSymbol symbol, double pixelRatio, Widget Function(Widget child) wrap,
    {required String id}) async {
  final overflow = symbol.overflow;
  final size = Size(symbol.width + overflow.horizontal, symbol.height + overflow.vertical);
  final image = await paintOffscreen(
      wrap(SizedBox.fromSize(
        size: size,
        child: Padding(
          padding: overflow,
          child: SizedBox(width: symbol.width, height: symbol.height, child: symbol.child),
        ),
      )),
      size,
      pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final box = opaqueBounds(rgba, image.width, image.height);
    if (box == null) return null;
    // The symbol's point, in the cropped picture (pixels)
    final anchor = (Offset(overflow.left, overflow.top) + symbol.anchor) * pixelRatio - Offset(box.left, box.top);
    return SymbolImage(
      id: "xc_$id",
      width: box.width.toInt(),
      height: box.height.toInt(),
      pixels: cropRgba(rgba, image.width, box),
      pixelRatio: pixelRatio,
      offset: (Offset(box.width / 2, box.height / 2) - anchor) / pixelRatio,
    );
  } finally {
    image.dispose();
  }
}

/// Smallest box (pixels) around everything that isn't fully transparent. Null when nothing is visible.
Rect? opaqueBounds(Uint8List rgba, int width, int height) {
  int top = height, bottom = -1, left = width, right = -1;
  for (int y = 0; y < height; y++) {
    final row = y * width * 4;
    int x = 0;
    while (x < width && rgba[row + x * 4 + 3] == 0) {
      x++;
    }
    if (x == width) continue;
    top = min(top, y);
    bottom = y;
    left = min(left, x);
    x = width - 1;
    while (rgba[row + x * 4 + 3] == 0) {
      x--;
    }
    right = max(right, x);
  }
  if (bottom < 0) return null;
  return Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}

/// The pixels of [box] from an RGBA image [width] pixels wide
Uint8List cropRgba(Uint8List rgba, int width, Rect box) {
  final w = box.width.toInt();
  final h = box.height.toInt();
  final out = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    final from = ((box.top.toInt() + y) * width + box.left.toInt()) * 4;
    out.setRange(y * w * 4, (y + 1) * w * 4, rgba, from);
  }
  return out;
}

/// Lays out and paints [widget] into an image of [size] (logical pixels), off screen.
///
/// Waits for things that load in the background (svg, images) to settle first.
Future<ui.Image> paintOffscreen(Widget widget, Size size, double pixelRatio) async {
  var dirty = false;
  final boundary = RenderRepaintBoundary();
  final positioned = RenderPositionedBox(alignment: Alignment.topLeft, child: boundary);
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final renderView = RenderView(
    view: dispatcher.implicitView ?? dispatcher.views.first,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints: BoxConstraints.tight(size * pixelRatio),
      devicePixelRatio: pixelRatio,
    ),
    child: positioned,
  );
  final pipelineOwner = PipelineOwner(onNeedVisualUpdate: () => dirty = true)..rootNode = renderView;
  renderView.prepareInitialFrame();
  final focusManager = FocusManager();
  final buildOwner = BuildOwner(focusManager: focusManager, onBuildScheduled: () => dirty = true);
  final root = RenderObjectToWidgetAdapter<RenderBox>(container: boundary, child: widget).attachToRenderTree(buildOwner);

  void pump() {
    buildOwner.buildScope(root);
    buildOwner.finalizeTree();
    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();
  }

  try {
    pump();
    // Draw again as things arrive, until it's been quiet for a few frames
    var quiet = 0;
    for (var i = 0; i < 60 && quiet < 3; i++) {
      await Future.delayed(const Duration(milliseconds: 16));
      if (dirty) {
        dirty = false;
        quiet = 0;
        pump();
      } else {
        quiet++;
      }
    }
    return await boundary.toImage(pixelRatio: pixelRatio);
  } finally {
    // Unmount, so states (image listeners etc.) are disposed
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary).attachToRenderTree(buildOwner, root);
    buildOwner.buildScope(root);
    buildOwner.finalizeTree();
    pipelineOwner.rootNode = null;
    boundary.dispose();
    positioned.dispose();
    renderView.dispose();
    pipelineOwner.dispose();
    focusManager.dispose();
  }
}
