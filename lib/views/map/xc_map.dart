import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import 'package:xcnav/dem_service.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/models/map_shapes.dart';
import 'package:xcnav/views/map/map_markers.dart';
import 'package:xcnav/views/map/map_symbols.dart';

typedef MapTapCallback = void Function(LatLng latlng, Offset screenPoint);

mb.Point toMbPoint(LatLng p) => mb.Point(coordinates: mb.Position(p.longitude, p.latitude));
LatLng fromMbPoint(mb.Point p) => LatLng(p.coordinates.lat.toDouble(), p.coordinates.lng.toDouble());

/// Max tilt we allow
const double mapMaxTilt = 75;

/// 3D terrain is only worth placing markers on from this zoom. Further out, ground height is a pixel or two.
const double terrainMarkerMinZoom = 8;

/// Elevation tiles to place things on the terrain with, at map [zoom]: a sample every few screen pixels,
/// so a screen full of markers only takes a handful of tiles.
int terrainDemZoom(double zoom) => (zoom.floor() - 1).clamp(0, demTileSource.maxNativeZoom);

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

  /// Repaint markers when this changes (camera moves, terrain heights arrive)
  Listenable get repaint => Listenable.merge([camera, demTilesLoaded]);

  /// Ground elevation (meters) at [point], when the map shows 3D terrain.
  /// Only near the view: further out it hardly shows, and loading it would push out the tiles in view.
  double? elevationAt(LatLng point) {
    final cam = camera.value;
    if (cam?.centerElevation == null || cam!.zoom < terrainMarkerMinZoom) return null;
    if (!cam.isNearView(point, margin: cam.size.shortestSide / 2)) return null;
    return sampleDemAt(point, terrainDemZoom(cam.zoom), fallbackLevels: 2);
  }

  /// Screen position of [point], sitting on the terrain when it's shown
  Offset? latLngToScreen(LatLng point) => camera.value?.latLngToScreen(point, elevation: elevationAt(point));

  /// Map position under [screen], on the terrain when it's shown
  LatLng? screenToLatLng(Offset screen) => camera.value?.screenToLatLng(screen, elevationAt: elevationAt);

  /// Hit values of the [layer] lines near [screenPoint]
  List<String> hitTestLines(ShapeLayer layer, Offset screenPoint, {double tolerance = 15}) {
    final cam = camera.value;
    if (cam == null) return [];
    return layer.hitTestLines(cam, screenPoint, tolerance: tolerance, elevationAt: elevationAt);
  }

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
    // Build on where the camera is headed, so eg. a follow update doesn't cut a tilt animation short
    final from = state._movingTo?.copyWith(size: cam.size) ?? cam;
    final target = from.copyWith(
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
    final cam = _state?._movingTo ?? camera.value;
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

/// Mapbox map with Flutter overlays.
///
/// - Base map: [tileSrc] at [opacity] (faded toward white), optionally on 3D [terrain].
/// - [shapes]: lines and areas, drawn natively by the map (in list order).
/// - [symbols]: markers drawn natively by the map, above the shapes (in list order). See [MapSymbol].
/// - [children]: Flutter widgets over the map, eg. `MarkerLayer` for markers that can be dragged.
///   They find the map with [XcMapScope].
class XcMap extends StatefulWidget {
  /// Draw a plain placeholder instead of the native map (widget tests can't host platform views).
  static bool useFakeMap = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  final XcMapController controller;
  final MapTileSrc tileSrc;
  final double opacity;

  final LatLng? initialCenter;
  final double initialZoom;
  final double initialTilt;

  /// Takes priority over [initialCenter]
  final LatLngBounds? initialBounds;
  final EdgeInsets initialPadding;
  final double initialMaxZoom;

  final List<ShapeLayer> shapes;
  final List<SymbolLayer> symbols;
  final List<Widget> children;

  final bool interactive;
  final bool rotateGestures;
  final bool tiltGestures;
  final double minZoom;
  final double maxZoom;

  /// Show 3D terrain
  final bool terrain;

  /// Room to leave around the Mapbox logo and attribution (bottom left), eg. for map controls
  final EdgeInsets ornamentMargin;

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
    this.initialTilt = 0,
    this.initialBounds,
    this.initialPadding = const EdgeInsets.all(20),
    this.initialMaxZoom = 15,
    this.shapes = const [],
    this.symbols = const [],
    this.children = const [],
    this.interactive = true,
    this.rotateGestures = true,
    this.tiltGestures = true,
    this.minZoom = 1,
    this.maxZoom = 20,
    this.terrain = false,
    this.ornamentMargin = const EdgeInsets.all(4),
    this.onTap,
    this.onLongPress,
    this.onCameraChanged,
    this.onUserGesture,
    this.onMapReady,
  });

  @override
  State<XcMap> createState() => _XcMapState();
}

class _XcMapState extends State<XcMap> with SingleTickerProviderStateMixin {
  mb.MapboxMap? _mapbox;
  MapCamera? _initialCamera;
  Size? _size;

  /// Loading a style resets the camera to the style's own. This is the camera to put back.
  MapCamera? _cameraForStyleLoad;

  /// Camera requested before the native map existed
  MapCamera? _pendingCamera;

  bool _styleLoaded = false;
  bool _readyNotified = false;

  /// Our camera is being put back after a style load. Until then the map is on the style's camera.
  bool _restoringCamera = false;

  /// Terrain is on in the current style
  bool _terrainOn = false;

  /// Shape layer ids on the map (or queued to be), bottom to top
  final List<String> _nativeOrder = [];

  /// Shape layer ids the map has actually added
  final Set<String> _nativeCreated = {};
  final Map<String, ShapeLayer> _sentLayer = {};
  final Map<String, Map<String, dynamic>> _sentData = {};
  bool _fadeAdded = false;

  /// Symbol layer ids on the map (or queued to be), bottom to top
  final List<String> _symbolOrder = [];
  final Set<String> _symbolCreated = {};
  final Map<String, Map<String, dynamic>> _sentSymbolData = {};

  /// Symbol pictures in the current style, by image key
  final Map<String, SymbolImage> _styleImages = {};
  final Set<String> _imagesRequested = {};
  bool _symbolSyncScheduled = false;

  /// Symbol layers with tap handlers. Those belong to the map, not the style, so they outlive style loads.
  final Set<String> _symbolInteractions = {};

  /// For drawing symbol pictures: what they'd have around them in the app
  double _pixelRatio = 1;
  Widget Function(Widget child) _imageWrap = (child) => child;

  /// Native calls run one at a time, in order
  Future _queue = Future.value();

  /// Bumped on every style (re)load. Queued calls for an older style are dropped.
  int _styleGeneration = 0;

  /// Steady speed camera moves, driven from here (the SDK only eases)
  late final Ticker _linearTicker;
  MapCamera? _linearFrom;
  MapCamera? _linearTo;
  Duration _linearDuration = Duration.zero;
  Duration? _linearStart;

  /// Camera an eased move is headed to, and when it gets there
  MapCamera? _easeTarget;
  DateTime? _easeEnd;

  // --- User gesture detection
  final Map<int, Offset> _pointers = {};
  bool _gestureReported = false;

  @override
  void initState() {
    super.initState();
    _linearTicker = createTicker(_onLinearTick);
    widget.controller._state = this;
    widget.controller.camera.addListener(_onCameraNotifier);
    demTilesLoaded.addListener(_onDemTileLoaded);
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
    if (oldWidget.interactive != widget.interactive ||
        oldWidget.rotateGestures != widget.rotateGestures ||
        oldWidget.tiltGestures != widget.tiltGestures) {
      _applyGestures();
    }
    if (oldWidget.tileSrc != widget.tileSrc) {
      // Everything we added goes with the old style. It's all re-added in _onStyleLoaded.
      _styleLoaded = false;
      _styleGeneration++;
      if (XcMap.useFakeMap) {
        _onStyleLoaded();
      } else {
        _cameraForStyleLoad = widget.controller.camera.value;
        _mapbox?.loadStyleURI(mapStyleUri(widget.tileSrc));
      }
    } else {
      if (oldWidget.terrain != widget.terrain) _enqueue(_applyTerrain);
      if (oldWidget.opacity != widget.opacity) _enqueue(_applyFade);
      _syncShapes();
      _syncSymbols();
    }
  }

  @override
  void dispose() {
    _linearTicker.dispose();
    demTilesLoaded.removeListener(_onDemTileLoaded);
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
          padding: widget.initialPadding,
          maxZoom: widget.initialMaxZoom,
          minZoom: widget.minZoom,
          tilt: widget.initialTilt);
    }
    return MapCamera(
        center: widget.initialCenter ?? const LatLng(37, -122),
        zoom: widget.initialZoom,
        tilt: widget.initialTilt,
        size: size);
  }

  static mb.CameraOptions _toMbCamera(MapCamera cam) =>
      mb.CameraOptions(center: toMbPoint(cam.center), zoom: cam.zoom, bearing: cam.bearing, pitch: cam.tilt);

  void _publishCamera(MapCamera cam) {
    double? elevation;
    if (_terrainOn) {
      // Ground height at the center. While its tile loads, keep the last one so markers don't hop.
      elevation = sampleDemAt(cam.center, terrainDemZoom(cam.zoom), fallbackLevels: 2) ??
          widget.controller.camera.value?.centerElevation;
    }
    widget.controller.camera.value =
        cam.copyWith(centerElevation: elevation, terrainExaggeration: terrainExaggeration, flat: elevation == null);
  }

  /// The tile under the center may have just loaded
  void _onDemTileLoaded() {
    final cam = widget.controller.camera.value;
    if (_terrainOn && cam != null) _publishCamera(cam);
  }

  void _setCameraFromMapbox(mb.CameraState state) {
    final size = _size;
    // Before the first style load the map is still on the style's default camera, not ours
    if (size == null || !_readyNotified || _restoringCamera) return;
    _publishCamera(MapCamera(
        center: fromMbPoint(state.center), zoom: state.zoom, bearing: state.bearing, tilt: state.pitch, size: size));
  }

  /// Where the camera is headed, while it's animating
  MapCamera? get _movingTo {
    if (_linearTicker.isActive) return _linearTo;
    final end = _easeEnd;
    return end != null && DateTime.now().isBefore(end) ? _easeTarget : null;
  }

  Future _moveCamera(MapCamera target, {Duration? duration, bool linear = false}) async {
    _linearTicker.stop();
    _easeEnd = null;
    final map = _mapbox;
    if (map == null) {
      // Fake map, or the native map isn't up yet
      _publishCamera(target);
      if (!XcMap.useFakeMap) _pendingCamera = target;
      return;
    }
    try {
      if (duration != null && linear) {
        _linearFrom = widget.controller.camera.value ?? target;
        _linearTo = target;
        _linearDuration = duration;
        _linearStart = null;
        _linearTicker.start();
      } else if (duration != null) {
        _easeTarget = target;
        _easeEnd = DateTime.now().add(duration);
        await map.easeTo(_toMbCamera(target), mb.MapAnimationOptions(duration: duration.inMilliseconds));
      } else {
        // Move overlays right away. The map confirms with a camera change event.
        _publishCamera(target);
        await map.setCamera(_toMbCamera(target));
      }
    } catch (e) {
      debugPrint("XcMap: camera move failed: $e");
    }
  }

  void _onLinearTick(Duration elapsed) {
    final from = _linearFrom;
    final to = _linearTo;
    final map = _mapbox;
    if (from == null || to == null || map == null) {
      _linearTicker.stop();
      return;
    }
    _linearStart ??= elapsed;
    final f = _linearDuration.inMicroseconds == 0
        ? 1.0
        : ((elapsed - _linearStart!).inMicroseconds / _linearDuration.inMicroseconds).clamp(0.0, 1.0);
    double lerp(double a, double b) => a + (b - a) * f;
    // Turn the short way around
    final bearingDelta = ((to.bearing - from.bearing + 540) % 360) - 180;
    final step = MapCamera(
        center:
            LatLng(lerp(from.center.latitude, to.center.latitude), lerp(from.center.longitude, to.center.longitude)),
        zoom: lerp(from.zoom, to.zoom),
        bearing: from.bearing + bearingDelta * f,
        tilt: lerp(from.tilt, to.tilt),
        size: to.size);
    map.setCamera(_toMbCamera(step));
    if (f >= 1) _linearTicker.stop();
  }

  void _onMapCreated(mb.MapboxMap map) {
    _mapbox = map;
    _cameraForStyleLoad ??= _initialCamera;
    final margin = widget.ornamentMargin;
    map.compass.updateSettings(mb.CompassSettings(enabled: false));
    map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));
    map.logo.updateSettings(mb.LogoSettings(
        enabled: false,
        position: mb.OrnamentPosition.BOTTOM_LEFT,
        marginLeft: margin.left,
        marginBottom: margin.bottom));
    map.attribution.updateSettings(mb.AttributionSettings(
        position: mb.OrnamentPosition.BOTTOM_LEFT, marginLeft: margin.left + 92, marginBottom: margin.bottom));
    map.setBounds(mb.CameraBoundsOptions(minZoom: widget.minZoom, maxZoom: widget.maxZoom, maxPitch: mapMaxTilt));
    _applyGestures();
    map.addInteraction(mb.TapInteraction.onMap((context) => _handleTap(fromMbPoint(context.point), long: false)));
    map.addInteraction(mb.LongTapInteraction.onMap((context) => _handleTap(fromMbPoint(context.point), long: true)));

    final pending = _pendingCamera;
    _pendingCamera = null;
    if (pending != null) _cameraForStyleLoad = pending;
  }

  void _applyGestures() {
    final enabled = widget.interactive;
    _mapbox?.gestures.updateSettings(mb.GesturesSettings(
      rotateEnabled: enabled && widget.rotateGestures,
      pitchEnabled: enabled && widget.tiltGestures,
      scrollEnabled: enabled,
      pinchToZoomEnabled: enabled,
      pinchPanEnabled: enabled,
      doubleTapToZoomInEnabled: enabled,
      doubleTouchToZoomOutEnabled: enabled,
      quickZoomEnabled: enabled,
    ));
  }

  // --- Style & shapes

  void _onStyleLoaded() {
    _styleLoaded = true;
    _styleGeneration++;
    _terrainOn = false;
    _nativeOrder.clear();
    _nativeCreated.clear();
    _sentLayer.clear();
    _sentData.clear();
    _fadeAdded = false;
    _symbolOrder.clear();
    _symbolCreated.clear();
    _sentSymbolData.clear();
    _styleImages.clear();
    _imagesRequested.clear();
    final map = _mapbox;
    if (map != null) {
      final camera = _cameraForStyleLoad;
      _cameraForStyleLoad = null;
      if (camera != null) _restoreCamera(map, camera);
      // Our overlays assume a flat (mercator) world
      _enqueue(() => map.setProjection(mb.StyleProjection(name: mb.StyleProjectionName.mercator)));
      // Symbols that move (eg. aircraft) would fade in again at every step
      _enqueue(() => map.setStyleTransition(mb.TransitionOptions(enablePlacementTransitions: false)));
      _enqueue(_applyStyleOverrides);
      _enqueue(_applyTerrain);
      _enqueue(_applyFade);
    }
    _syncShapes();
    _syncSymbols();
    if (!_readyNotified) {
      _readyNotified = true;
      widget.onMapReady?.call();
    }
  }

  Future _restoreCamera(mb.MapboxMap map, MapCamera camera) async {
    _linearTicker.stop();
    _easeEnd = null;
    _restoringCamera = true;
    try {
      await map.setCamera(_toMbCamera(camera));
    } catch (e) {
      debugPrint("XcMap: camera move failed: $e");
    } finally {
      _restoringCamera = false;
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
        // The top shape layer still goes under the symbols
        below ??= _symbolOrder.isEmpty ? null : _symbolLayerId(_symbolOrder.first);
        _nativeOrder.insert(insertAt, layer.id);
        _sentData[layer.id] = data;
        if (_mapbox != null) _enqueue(() => _addShapeLayer(layer.id, data, below));
      } else if (!const DeepCollectionEquality().equals(_sentData[layer.id], data)) {
        _sentData[layer.id] = data;
        if (_mapbox != null) {
          _enqueue(() => _mapbox!.setStyleSourceProperty(_sourceId(layer.id), "data", jsonEncode(data)));
        }
      }
    }

    // Layers that went away stay in place (keeps the order simple), just empty.
    final ids = layers.map((e) => e.id).toSet();
    for (final id in _nativeOrder) {
      if (!ids.contains(id) && ((_sentData[id]?["features"] as List?)?.isNotEmpty ?? false)) {
        final empty = const ShapeLayer("").toGeoJson();
        _sentData[id] = empty;
        _sentLayer.remove(id);
        if (_mapbox != null) _enqueue(() => _mapbox!.setStyleSourceProperty(_sourceId(id), "data", jsonEncode(empty)));
      }
    }
  }

  Future _addShapeLayer(String id, Map<String, dynamic> data, String? below) async {
    final map = _mapbox!;
    final source = _sourceId(id);
    await map.addStyleSource(source, jsonEncode({"type": "geojson", "data": data}));

    Future add(Map<String, dynamic> layer) =>
        map.addStyleLayer(jsonEncode(layer), below == null ? null : mb.LayerPosition(below: below));

    final isLine = [
      "==",
      ["get", "kind"],
      "line"
    ];
    await add({
      "id": _styleLayerId(id, "fill"),
      "type": "fill",
      "source": source,
      "filter": [
        "==",
        ["get", "kind"],
        "fill"
      ],
      "paint": {
        "fill-color": ["get", "color"]
      },
    });
    await add({
      "id": _styleLayerId(id, "casing"),
      "type": "line",
      "source": source,
      "filter": [
        "all",
        isLine,
        [
          ">",
          ["get", "border"],
          0
        ]
      ],
      "layout": {"line-cap": "round", "line-join": "round"},
      "paint": {
        "line-color": ["get", "borderColor"],
        "line-width": [
          "+",
          ["get", "width"],
          [
            "*",
            2,
            ["get", "border"]
          ]
        ],
      },
    });
    for (final pattern in LinePattern.values) {
      await add({
        "id": _styleLayerId(id, pattern.name),
        "type": "line",
        "source": source,
        "filter": [
          "all",
          isLine,
          [
            "==",
            ["get", "pattern"],
            pattern.name
          ]
        ],
        "layout": {"line-cap": pattern == LinePattern.dashed ? "butt" : "round", "line-join": "round"},
        "paint": {
          "line-color": ["get", "color"],
          "line-width": ["get", "width"],
          if (lineDashArrays[pattern] != null) "line-dasharray": lineDashArrays[pattern],
        },
      });
    }
    _nativeCreated.add(id);
  }

  // --- Symbols

  static String _symbolLayerId(String layerId) => "xc_sym_$layerId";

  void _syncSymbols() {
    final map = _mapbox;
    if (!_styleLoaded || map == null) return;
    final layers = widget.symbols;

    // Pictures not in the style yet get drawn and added, then their layer is sent again
    final used = <String>{};
    for (final layer in layers) {
      for (final symbol in layer.symbols) {
        if (used.add(symbol.imageKey) && !_styleImages.containsKey(symbol.imageKey)) _requestSymbolImage(symbol);
      }
    }

    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i];
      final data = layer.toGeoJson(_styleImages);
      if (!_symbolOrder.contains(layer.id)) {
        // Slot it in below the next symbol layer that's already on the map
        String? below;
        int insertAt = _symbolOrder.length;
        for (int j = i + 1; j < layers.length; j++) {
          final index = _symbolOrder.indexOf(layers[j].id);
          if (index >= 0) {
            below = _symbolLayerId(layers[j].id);
            insertAt = index;
            break;
          }
        }
        _symbolOrder.insert(insertAt, layer.id);
        _sentSymbolData[layer.id] = data;
        _enqueue(() => _addSymbolLayer(layer, data, below));
      } else if (!const DeepCollectionEquality().equals(_sentSymbolData[layer.id], data)) {
        _sentSymbolData[layer.id] = data;
        _enqueue(() => map.setStyleSourceProperty(_symbolLayerId(layer.id), "data", jsonEncode(data)));
      }
    }

    // Layers that went away stay in place (keeps the order simple), just empty.
    final ids = layers.map((e) => e.id).toSet();
    for (final id in _symbolOrder) {
      if (!ids.contains(id) && ((_sentSymbolData[id]?["features"] as List?)?.isNotEmpty ?? false)) {
        final empty = const SymbolLayer("").toGeoJson(const {});
        _sentSymbolData[id] = empty;
        _enqueue(() => map.setStyleSourceProperty(_symbolLayerId(id), "data", jsonEncode(empty)));
      }
    }

    // Pictures nothing shows any more
    for (final key in _styleImages.keys.where((e) => !used.contains(e)).toList()) {
      final image = _styleImages.remove(key)!;
      _imagesRequested.remove(key);
      _enqueue(() => map.removeStyleImage(image.id));
    }
  }

  void _requestSymbolImage(MapSymbol symbol) {
    final key = symbol.imageKey;
    if (!_imagesRequested.add(key)) return;
    final generation = _styleGeneration;
    SymbolImages.instance.get(symbol, _pixelRatio, _imageWrap).then((image) {
      if (image == null || !mounted || generation != _styleGeneration) return;
      _enqueue(() async {
        await _mapbox!.addImage(image.id, image.pixelRatio,
            mb.StyleImage.rgba(width: image.width, height: image.height, pixels: image.pixels));
        _styleImages[key] = image;
        _scheduleSymbolSync();
      });
    });
  }

  /// Pictures come in one by one. Send them on together.
  void _scheduleSymbolSync() {
    if (_symbolSyncScheduled) return;
    _symbolSyncScheduled = true;
    Future.delayed(const Duration(milliseconds: 50), () {
      _symbolSyncScheduled = false;
      if (mounted) _syncSymbols();
    });
  }

  Future _addSymbolLayer(SymbolLayer layer, Map<String, dynamic> data, String? below) async {
    final map = _mapbox!;
    final id = _symbolLayerId(layer.id);
    await map.addStyleSource(id, jsonEncode({"type": "geojson", "data": data}));
    await map.addStyleLayer(
        jsonEncode({
          "id": id,
          "type": "symbol",
          "source": id,
          if (layer.minZoom != null) "minzoom": layer.minZoom,
          "layout": {
            "icon-image": ["get", "image"],
            "icon-rotate": ["get", "rotate"],
            "icon-offset": ["get", "offset"],
            "icon-rotation-alignment": layer.rotateWithMap ? "map" : "viewport",
            // Upright symbols stand up, facing the viewer, when the map is tilted. Ones that turn with the map lie
            // flat on it: standing up, Mapbox gets their angle wrong on 3D terrain (90° off).
            "icon-pitch-alignment": layer.rotateWithMap ? "map" : "viewport",
            "icon-allow-overlap": true,
            "icon-ignore-placement": true,
            "symbol-z-order": "source",
          },
          "paint": {
            "icon-opacity": ["get", "opacity"]
          },
        }),
        below == null ? null : mb.LayerPosition(below: below));
    _symbolCreated.add(layer.id);

    if (_symbolInteractions.add(layer.id)) {
      // Symbols without a handler let taps through to the map
      map.addInteraction(
          mb.TapInteraction(mb.FeaturesetDescriptor(layerId: id),
              (feature, _) => _onSymbolTap(layer.id, feature.properties["id"], long: false),
              filter: jsonEncode([
                "==",
                ["get", "tap"],
                true
              ])),
          interactionID: "${id}_tap");
      map.addInteraction(
          mb.LongTapInteraction(mb.FeaturesetDescriptor(layerId: id),
              (feature, _) => _onSymbolTap(layer.id, feature.properties["id"], long: true),
              filter: jsonEncode([
                "==",
                ["get", "longTap"],
                true
              ])),
          interactionID: "${id}_longTap");
    }
  }

  void _onSymbolTap(String layerId, Object? symbolId, {required bool long}) {
    final symbol = widget.symbols.where((e) => e.id == layerId).firstOrNull?.byId(symbolId);
    (long ? symbol?.onLongPress : symbol?.onTap)?.call();
  }

  /// Our tweaks to the hosted style, eg. deeper hillshade on topo
  Future _applyStyleOverrides() async {
    final map = _mapbox;
    if (map == null) return;
    for (final layer in styleOverridesFor(widget.tileSrc).entries) {
      if (!await map.styleLayerExists(layer.key)) continue;
      for (final property in layer.value.entries) {
        await map.setStyleLayerProperty(layer.key, property.key, property.value);
      }
    }
    final additions = styleAdditionsFor(widget.tileSrc);
    // Added layers may draw from the elevation tiles (eg. relief shading), with or without 3D terrain
    if (additions.isNotEmpty) await _addDemSource();
    for (final addition in additions) {
      final below = addition.below;
      await map.addStyleLayer(jsonEncode(addition.layer),
          below != null && await map.styleLayerExists(below) ? mb.LayerPosition(below: below) : null);
    }
  }

  /// Elevation tiles, when the style doesn't have them itself. Returns the source id.
  Future<String> _addDemSource() async {
    final map = _mapbox!;
    final dem = terrainSourceFor(widget.tileSrc);
    if (dem.source != null && !await map.styleSourceExists(dem.id)) {
      await map.addStyleSource(dem.id, jsonEncode(dem.source));
    }
    return dem.id;
  }

  static const _fadeLayerId = "xc_fade";
  static const _skyLayerId = "xc_sky";

  /// Base map opacity: a white layer between the base map and our shapes.
  Future _applyFade() async {
    final map = _mapbox;
    if (map == null || !_styleLoaded) return;
    if (_fadeAdded) {
      await map.removeStyleLayer(_fadeLayerId);
      _fadeAdded = false;
    }
    if (widget.opacity < 1) {
      final lowestShape = _nativeOrder.where(_nativeCreated.contains).firstOrNull;
      final lowestSymbol = _symbolOrder.where(_symbolCreated.contains).firstOrNull;
      final below = lowestShape != null
          ? _styleLayerId(lowestShape, shapeStyleLayers.first)
          : (lowestSymbol != null ? _symbolLayerId(lowestSymbol) : null);
      await map.addStyleLayer(
          jsonEncode({
            "id": _fadeLayerId,
            "type": "background",
            "paint": {"background-color": "#ffffff", "background-opacity": 1 - widget.opacity},
          }),
          below == null ? null : mb.LayerPosition(below: below));
      _fadeAdded = true;
    }
  }

  /// 3D terrain, with a sky for when the view is tilted up to the horizon
  Future _applyTerrain() async {
    final map = _mapbox;
    if (map == null || !_styleLoaded) return;
    if (widget.terrain) {
      final demId = await _addDemSource();
      await map.setStyleTerrain(jsonEncode({"source": demId, "exaggeration": terrainExaggeration}));
      if (!await map.styleLayerExists(_skyLayerId)) {
        await map.addStyleLayer(
            jsonEncode({
              "id": _skyLayerId,
              "type": "sky",
              "paint": {"sky-type": "atmosphere", "sky-atmosphere-sun-intensity": 8},
            }),
            null);
      }
      _terrainOn = true;
    } else if (_terrainOn) {
      await map.removeStyleTerrain();
      if (await map.styleLayerExists(_skyLayerId)) await map.removeStyleLayer(_skyLayerId);
      _terrainOn = false;
    }
    final cam = widget.controller.camera.value;
    if (cam != null && mounted) _publishCamera(cam);
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
    // Gestures stop camera animations
    _linearTicker.stop();
    _easeEnd = null;
    widget.onUserGesture?.call();
  }

  void _handleTap(LatLng latlng, {required bool long}) {
    final screen = widget.controller.latLngToScreen(latlng) ?? Offset.zero;
    (long ? widget.onLongPress : widget.onTap)?.call(latlng, screen);
  }

  Widget _buildNativeMap() {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: mb.MapWidget(
        // Only read when the map is created. Style changes go through loadStyleURI.
        styleUri: mapStyleUri(widget.tileSrc),
        onMapCreated: _onMapCreated,
        onStyleLoadedListener: (_) => _onStyleLoaded(),
        onCameraChangeListener: (event) => _setCameraFromMapbox(event.cameraState),
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
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final pixelRatio = _pixelRatio;
    final textScaler = MediaQuery.textScalerOf(context);
    final theme = Theme.of(context);
    final textStyle = DefaultTextStyle.of(context).style;
    final textDirection = Directionality.of(context);
    _imageWrap = (child) => MediaQuery(
        data: MediaQueryData(devicePixelRatio: pixelRatio, textScaler: textScaler),
        child: Theme(
            data: theme,
            child: Directionality(
                textDirection: textDirection,
                child: DefaultTextStyle(style: textStyle, child: TickerMode(enabled: false, child: child)))));

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
          XcMap.useFakeMap ? _FakeMapView(state: this) : _buildNativeMap(),
          XcMapScope(
              controller: widget.controller,
              child: Stack(fit: StackFit.expand, children: [
                // No map engine to draw the symbols, so Flutter does
                if (XcMap.useFakeMap)
                  for (final layer in widget.symbols)
                    MarkerLayer(
                        markers: layer.symbols
                            .map((e) => e.toMarker(layer.id, rotateWithMap: layer.rotateWithMap))
                            .toList()),
                ...widget.children,
              ])),
        ]),
      );
    });
  }
}

/// Stand-in for the native map in widget tests. Taps and drags work, there's just nothing to see.
class _FakeMapView extends StatelessWidget {
  final _XcMapState state;

  const _FakeMapView({required this.state});

  LatLng? _toLatLng(Offset local) => state.widget.controller.screenToLatLng(local);

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
