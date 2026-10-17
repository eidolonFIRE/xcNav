import 'dart:async';
import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/models/map_shapes.dart';

typedef MapTapCallback = void Function(LatLng latlng, Offset screenPoint);

ml.LatLng toMlLatLng(LatLng p) => ml.LatLng(p.latitude, p.longitude);
LatLng fromMlLatLng(ml.LatLng p) => LatLng(p.latitude, p.longitude);

/// Max tilt MapLibre Native allows
const double mapMaxTilt = 60;

/// Drives an [XcMap] (camera moves) and publishes where it's looking ([camera]).
class XcMapController {
  /// Null until the map has a size
  final ValueNotifier<MapCamera?> camera;

  /// `floor(zoom)`, for layers that only change at whole zoom levels
  final ValueNotifier<int> zoomLevel = ValueNotifier(0);

  /// Camera bearing, rounded to a degree. For layers drawn relative to the screen.
  final ValueNotifier<double> bearing = ValueNotifier(0);

  _XcMapState? _state;

  XcMapController() : camera = ValueNotifier(null) {
    camera.addListener(_updateDerived);
  }

  /// A camera that never moves (static previews)
  XcMapController.fixed(MapCamera fixedCamera) : camera = ValueNotifier(fixedCamera) {
    _updateDerived();
  }

  void _updateDerived() {
    final cam = camera.value;
    if (cam == null) return;
    zoomLevel.value = cam.zoom.floor();
    bearing.value = cam.bearing.roundToDouble();
  }

  bool get isReady => camera.value != null && _state != null;

  /// Map widget relative position of a global (screen) position
  Offset? globalToLocal(Offset global) {
    final box = _state?.context.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  /// Move the camera. Animates when given a [duration]; [linear] keeps a steady speed (for following GPS updates).
  Future moveTo(
      {LatLng? center, double? zoom, double? bearing, double? tilt, Duration? duration, bool linear = false}) async {
    final cam = camera.value;
    final state = _state;
    if (cam == null || state == null) return;
    final target = cam.copyWith(
        center: center,
        zoom: zoom?.clamp(state.widget.minZoom, state.widget.maxZoom).toDouble(),
        bearing: bearing,
        tilt: tilt?.clamp(0, mapMaxTilt).toDouble());
    if (target == cam) return;
    await state._moveCamera(target, duration: duration, linear: linear);
  }

  /// Show all of [bounds]. Keeps the current bearing and tilt.
  Future fitBounds(LatLngBounds bounds,
      {EdgeInsets padding = const EdgeInsets.all(20), double minZoom = 1, double maxZoom = 17, Duration? duration}) {
    final cam = camera.value;
    if (cam == null) return Future.value();
    final fit = MapCamera.fit(bounds, cam.size,
        padding: padding, bearing: cam.bearing, tilt: cam.tilt, minZoom: minZoom, maxZoom: maxZoom);
    return moveTo(center: fit.center, zoom: fit.zoom, duration: duration);
  }

  Future zoomBy(double delta) {
    final cam = camera.value;
    if (cam == null) return Future.value();
    return moveTo(zoom: cam.zoom + delta, duration: const Duration(milliseconds: 250));
  }
}

/// Gives map overlay layers (markers etc.) access to the map's controller.
class XcMapScope extends InheritedWidget {
  final XcMapController controller;

  const XcMapScope({super.key, required this.controller, required super.child});

  static XcMapController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<XcMapScope>();
    assert(scope != null, "No XcMap above this widget");
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(XcMapScope oldWidget) => oldWidget.controller != controller;
}

/// MapLibre map with Flutter overlays.
///
/// - Base map: [tileSrc] at [opacity] (faded toward white).
/// - [shapes]: lines and areas, drawn natively by MapLibre (in list order).
/// - [children]: Flutter widgets over the map, eg. `MarkerLayer`. They find the map with [XcMapScope].
class XcMap extends StatefulWidget {
  /// Draw a plain placeholder instead of the native map (widget tests can't host platform views).
  static bool useFakeMap = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  final XcMapController controller;
  final MapTileSrc tileSrc;
  final double opacity;

  final LatLng? initialCenter;
  final double initialZoom;

  /// Takes priority over [initialCenter]
  final LatLngBounds? initialBounds;
  final EdgeInsets initialPadding;
  final double initialMaxZoom;

  final List<ShapeLayer> shapes;
  final List<Widget> children;

  final bool interactive;
  final bool rotateGestures;
  final bool tiltGestures;
  final double minZoom;
  final double maxZoom;

  /// Try MapLibre's 3D terrain (MapTiler maps). MapLibre Native doesn't support it yet, so it's a no-op on mobile.
  final bool terrain;

  final MapTapCallback? onTap;
  final MapTapCallback? onLongPress;
  final void Function(MapCamera camera)? onCameraChanged;

  /// The user started panning / zooming / rotating the map
  final VoidCallback? onUserGesture;

  /// Style loaded and the camera is known
  final VoidCallback? onMapReady;

  const XcMap({
    super.key,
    required this.controller,
    this.tileSrc = MapTileSrc.topo,
    this.opacity = 1.0,
    this.initialCenter,
    this.initialZoom = 10,
    this.initialBounds,
    this.initialPadding = const EdgeInsets.all(20),
    this.initialMaxZoom = 15,
    this.shapes = const [],
    this.children = const [],
    this.interactive = true,
    this.rotateGestures = true,
    this.tiltGestures = true,
    this.minZoom = 1,
    this.maxZoom = 20,
    this.terrain = false,
    this.onTap,
    this.onLongPress,
    this.onCameraChanged,
    this.onUserGesture,
    this.onMapReady,
  });

  @override
  State<XcMap> createState() => _XcMapState();
}

class _XcMapState extends State<XcMap> {
  ml.MapLibreMapController? _ml;
  MapCamera? _initialCamera;
  Size? _size;

  /// Camera requested before the native map existed
  MapCamera? _pendingCamera;

  bool _styleLoaded = false;
  bool _readyNotified = false;

  /// Shape layer ids on the map (or queued to be), bottom to top
  final List<String> _nativeOrder = [];

  /// Shape layer ids MapLibre has actually added
  final Set<String> _nativeCreated = {};
  final Map<String, ShapeLayer> _sentLayer = {};
  final Map<String, Map<String, dynamic>> _sentData = {};
  bool _fadeAdded = false;

  /// Native calls run one at a time, in order
  Future _queue = Future.value();

  /// Bumped on every style (re)load. Queued calls for an older style are dropped.
  int _styleGeneration = 0;

  // --- User gesture detection
  final Map<int, Offset> _pointers = {};
  bool _gestureReported = false;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    widget.controller.camera.addListener(_onCameraNotifier);
  }

  @override
  void didUpdateWidget(covariant XcMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.camera.removeListener(_onCameraNotifier);
      if (oldWidget.controller._state == this) oldWidget.controller._state = null;
      widget.controller._state = this;
      widget.controller.camera.addListener(_onCameraNotifier);
    }
    if (oldWidget.tileSrc != widget.tileSrc) {
      // MapLibreMap swaps the style. Everything we added goes with it; re-added in _onStyleLoaded.
      _styleLoaded = false;
      _styleGeneration++;
      if (XcMap.useFakeMap) _onStyleLoaded();
    } else {
      if (oldWidget.opacity != widget.opacity) _enqueue(_applyFade);
      _syncShapes();
    }
  }

  @override
  void dispose() {
    widget.controller.camera.removeListener(_onCameraNotifier);
    if (widget.controller._state == this) widget.controller._state = null;
    super.dispose();
  }

  void _onCameraNotifier() {
    final cam = widget.controller.camera.value;
    if (cam != null) widget.onCameraChanged?.call(cam);
  }

  // --- Camera

  MapCamera _buildInitialCamera(Size size) {
    if (widget.initialBounds != null) {
      return MapCamera.fit(widget.initialBounds!, size,
          padding: widget.initialPadding, maxZoom: widget.initialMaxZoom, minZoom: widget.minZoom);
    }
    return MapCamera(center: widget.initialCenter ?? const LatLng(37, -122), zoom: widget.initialZoom, size: size);
  }

  static ml.CameraPosition _toMlCamera(MapCamera cam) =>
      ml.CameraPosition(target: toMlLatLng(cam.center), zoom: cam.zoom, bearing: cam.bearing, tilt: cam.tilt);

  void _setCameraFromMl(ml.CameraPosition? pos) {
    final size = _size;
    if (pos == null || size == null) return;
    widget.controller.camera.value =
        MapCamera(center: fromMlLatLng(pos.target), zoom: pos.zoom, bearing: pos.bearing, tilt: pos.tilt, size: size);
  }

  Future _moveCamera(MapCamera target, {Duration? duration, bool linear = false}) async {
    final mlc = _ml;
    if (mlc == null) {
      // Fake map, or the native map isn't up yet
      widget.controller.camera.value = target;
      if (!XcMap.useFakeMap) _pendingCamera = target;
      return;
    }
    final update = ml.CameraUpdate.newCameraPosition(_toMlCamera(target));
    try {
      if (duration != null && linear) {
        await mlc.easeCamera(update, duration: duration, interpolation: ml.CameraAnimationInterpolation.linear);
      } else if (duration != null) {
        await mlc.animateCamera(update, duration: duration);
      } else {
        // Move overlays right away. MapLibre confirms with a camera move event.
        widget.controller.camera.value = target;
        await mlc.moveCamera(update);
      }
    } catch (e) {
      debugPrint("XcMap: camera move failed: $e");
    }
  }

  void _onMapCreated(ml.MapLibreMapController controller) {
    _ml = controller;
    final pending = _pendingCamera;
    _pendingCamera = null;
    if (pending != null) {
      controller.moveCamera(ml.CameraUpdate.newCameraPosition(_toMlCamera(pending)));
    }
  }

  // --- Style & shapes

  void _onStyleLoaded() {
    _styleLoaded = true;
    _styleGeneration++;
    _nativeOrder.clear();
    _nativeCreated.clear();
    _sentLayer.clear();
    _sentData.clear();
    _fadeAdded = false;
    if (_ml != null) {
      _enqueue(_applyFade);
      _enqueue(_tryTerrain);
    }
    _syncShapes();
    if (!_readyNotified) {
      _readyNotified = true;
      widget.onMapReady?.call();
    }
  }

  void _enqueue(Future Function() task) {
    final generation = _styleGeneration;
    _queue = _queue.then((_) {
      if (generation != _styleGeneration || !mounted) return null;
      return task();
    }).catchError((e) {
      debugPrint("XcMap: native update failed: $e");
    });
  }

  static String _sourceId(String layerId) => "xc_$layerId";
  static String _styleLayerId(String layerId, String part) => "xc_${layerId}_$part";

  void _syncShapes() {
    if (!_styleLoaded) return;
    final layers = widget.shapes;
    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i];
      if (identical(_sentLayer[layer.id], layer)) continue;
      _sentLayer[layer.id] = layer;
      final data = layer.toGeoJson();

      if (!_nativeOrder.contains(layer.id)) {
        // Slot it in below the next layer that's already on the map
        String? below;
        int insertAt = _nativeOrder.length;
        for (int j = i + 1; j < layers.length; j++) {
          final index = _nativeOrder.indexOf(layers[j].id);
          if (index >= 0) {
            below = _styleLayerId(layers[j].id, shapeStyleLayers.first);
            insertAt = index;
            break;
          }
        }
        _nativeOrder.insert(insertAt, layer.id);
        _sentData[layer.id] = data;
        if (_ml != null) _enqueue(() => _addShapeLayer(layer.id, data, below));
      } else if (!const DeepCollectionEquality().equals(_sentData[layer.id], data)) {
        _sentData[layer.id] = data;
        if (_ml != null) _enqueue(() => _ml!.setGeoJsonSource(_sourceId(layer.id), data));
      }
    }

    // Layers that went away stay in place (keeps the order simple), just empty.
    final ids = layers.map((e) => e.id).toSet();
    for (final id in _nativeOrder) {
      if (!ids.contains(id) && ((_sentData[id]?["features"] as List?)?.isNotEmpty ?? false)) {
        final empty = const ShapeLayer("").toGeoJson();
        _sentData[id] = empty;
        _sentLayer.remove(id);
        if (_ml != null) _enqueue(() => _ml!.setGeoJsonSource(_sourceId(id), empty));
      }
    }
  }

  Future _addShapeLayer(String id, Map<String, dynamic> data, String? below) async {
    final mlc = _ml!;
    final source = _sourceId(id);
    await mlc.addGeoJsonSource(source, data);

    final isLine = ["==", ["get", "kind"], "line"];
    await mlc.addFillLayer(
        source, _styleLayerId(id, "fill"), const ml.FillLayerProperties(fillColor: ["get", "color"]),
        filter: ["==", ["get", "kind"], "fill"], belowLayerId: below, enableInteraction: false);
    await mlc.addLineLayer(
        source,
        _styleLayerId(id, "casing"),
        const ml.LineLayerProperties(
          lineColor: ["get", "borderColor"],
          lineWidth: [
            "+",
            ["get", "width"],
            [
              "*",
              2,
              ["get", "border"]
            ]
          ],
          lineCap: "round",
          lineJoin: "round",
        ),
        filter: [
          "all",
          isLine,
          [">", ["get", "border"], 0]
        ],
        belowLayerId: below,
        enableInteraction: false);
    for (final pattern in LinePattern.values) {
      await mlc.addLineLayer(
          source,
          _styleLayerId(id, pattern.name),
          ml.LineLayerProperties(
            lineColor: const ["get", "color"],
            lineWidth: const ["get", "width"],
            lineDasharray: lineDashArrays[pattern],
            lineCap: pattern == LinePattern.dashed ? "butt" : "round",
            lineJoin: "round",
          ),
          filter: [
            "all",
            isLine,
            ["==", ["get", "pattern"], pattern.name]
          ],
          belowLayerId: below,
          enableInteraction: false);
    }
    _nativeCreated.add(id);
  }

  static const _fadeLayerId = "xc_fade";

  /// Base map opacity: a white layer between the base map and our shapes.
  Future _applyFade() async {
    final mlc = _ml;
    if (mlc == null || !_styleLoaded) return;
    if (_fadeAdded) {
      await mlc.removeLayer(_fadeLayerId);
      _fadeAdded = false;
    }
    if (widget.opacity < 1) {
      final lowestShape = _nativeOrder.where(_nativeCreated.contains).firstOrNull;
      await mlc.addBackgroundLayer(
          _fadeLayerId, ml.BackgroundLayerProperties(backgroundColor: "#ffffff", backgroundOpacity: 1 - widget.opacity),
          belowLayerId: lowestShape != null ? _styleLayerId(lowestShape, shapeStyleLayers.first) : null);
      _fadeAdded = true;
    }
  }

  Future _tryTerrain() async {
    final mlc = _ml;
    if (!widget.terrain || mlc == null || widget.tileSrc == MapTileSrc.sectional) return;
    try {
      // Topo comes with a DEM source. Satellite needs one.
      String source = "terrain_rgb";
      if (widget.tileSrc == MapTileSrc.satellite) {
        source = "xc_terrain";
        // Throws where terrain isn't supported, before we add a source for nothing
        await mlc.setTerrain(null);
        await mlc.addSource(source, ml.RasterDemSourceProperties(url: maptilerTerrainUrl));
      }
      await mlc.setTerrain(ml.TerrainProperties(source: source, exaggeration: 1.3));
    } on UnsupportedError {
      // MapLibre Native has no 3D terrain yet. Tilt still gives a perspective view.
    }
  }

  // --- Gestures

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length > 1) _reportGesture();
  }

  void _onPointerMove(PointerMoveEvent event) {
    final start = _pointers[event.pointer];
    if (start != null && (event.localPosition - start).distance > kTouchSlop) _reportGesture();
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) _gestureReported = false;
  }

  void _reportGesture() {
    if (_gestureReported || !widget.interactive) return;
    _gestureReported = true;
    widget.onUserGesture?.call();
  }

  void _handleTap(LatLng latlng, {required bool long}) {
    final screen = widget.controller.camera.value?.latLngToScreen(latlng) ?? Offset.zero;
    (long ? widget.onLongPress : widget.onTap)?.call(latlng, screen);
  }

  Widget _buildNativeMap(MapCamera initial) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: ml.MapLibreMap(
        styleString: mapStyleString(widget.tileSrc),
        initialCameraPosition: _toMlCamera(initial),
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleLoaded,
        trackCameraPosition: true,
        onCameraMove: _setCameraFromMl,
        onCameraIdle: () => _setCameraFromMl(_ml?.cameraPosition),
        onMapClick: (point, latlng) => _handleTap(fromMlLatLng(latlng), long: false),
        onMapLongClick: (point, latlng) => _handleTap(fromMlLatLng(latlng), long: true),
        compassEnabled: false,
        logoEnabled: false,
        rotateGesturesEnabled: widget.interactive && widget.rotateGestures,
        tiltGesturesEnabled: widget.interactive && widget.tiltGestures,
        scrollGesturesEnabled: widget.interactive,
        zoomGesturesEnabled: widget.interactive,
        doubleClickZoomEnabled: widget.interactive,
        minMaxZoomPreference: ml.MinMaxZoomPreference(widget.minZoom, widget.maxZoom),
        // We don't use the annotation managers. Skipping them is much faster on Android.
        annotationOrder: const [],
        dragEnabled: false,
        attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
        gestureRecognizers: widget.interactive
            ? <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (_size != size) {
        final firstLayout = _size == null;
        _size = size;
        _initialCamera ??= _buildInitialCamera(size);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final cam = widget.controller.camera.value;
          widget.controller.camera.value = (firstLayout || cam == null) ? _initialCamera : cam.copyWith(size: size);
          if (firstLayout && XcMap.useFakeMap) _onStyleLoaded();
        });
      }

      return ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          XcMap.useFakeMap ? _FakeMapView(state: this) : _buildNativeMap(_initialCamera!),
          XcMapScope(controller: widget.controller, child: Stack(fit: StackFit.expand, children: widget.children)),
        ]),
      );
    });
  }
}

/// Stand-in for the native map in widget tests. Taps and drags work, there's just nothing to see.
class _FakeMapView extends StatelessWidget {
  final _XcMapState state;

  const _FakeMapView({required this.state});

  LatLng? _toLatLng(Offset local) => state.widget.controller.camera.value?.screenToLatLng(local);

  @override
  Widget build(BuildContext context) {
    final widget = state.widget;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final latlng = _toLatLng(details.localPosition);
        if (latlng != null) widget.onTap?.call(latlng, details.localPosition);
      },
      onLongPressStart: (details) {
        final latlng = _toLatLng(details.localPosition);
        if (latlng != null) widget.onLongPress?.call(latlng, details.localPosition);
      },
      onPanStart: widget.interactive ? (_) => widget.onUserGesture?.call() : null,
      onPanUpdate: widget.interactive
          ? (details) {
              final cam = widget.controller.camera.value;
              if (cam == null) return;
              widget.controller.camera.value =
                  cam.copyWith(center: cam.screenToLatLng(cam.size.center(Offset.zero) - details.delta));
            }
          : null,
      child: Container(color: const Color(0xffdfe6da)),
    );
  }
}
