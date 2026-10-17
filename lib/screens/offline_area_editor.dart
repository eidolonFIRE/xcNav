import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/models/map_shapes.dart';
import 'package:xcnav/models/offline_area.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/services/offline_map_service.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/views/map/map_markers.dart';
import 'package:xcnav/views/map/poly_editor.dart';
import 'package:xcnav/views/map/xc_map.dart';

class OfflineAreaEditor extends StatefulWidget {
  const OfflineAreaEditor({super.key});

  @override
  State<OfflineAreaEditor> createState() => _OfflineAreaEditorState();
}

class _OfflineAreaEditorState extends State<OfflineAreaEditor> {
  /// Inset of the "visible area" frame from the map edges
  static const frameMargin = 24.0;

  /// Counting tiles is expensive. Wait for the user to stop moving things before re-estimating.
  static const estimateDelay = Duration(seconds: 2);

  final mapController = XcMapController();
  bool mapReady = false;

  bool polygonMode = false;
  final List<LatLng> polyPoints = [];
  late final MapPolyEditor polyEditor;

  final Set<MapTileSrc> layers = {};

  /// Selected layer shown on the map (most recently enabled)
  late MapTileSrc previewLayer;

  DownloadEstimate? estimate;
  bool estimating = false;
  int _estimateSeq = 0;
  bool _estimateInFlight = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    previewLayer = settingsMgr.mainMapTileSrc.value;
    layers.add(previewLayer);
    polyEditor = MapPolyEditor(
      closed: true,
      points: polyPoints,
      pointIcon: const Icon(Icons.crop_square, size: 22, color: Colors.black),
      intermediateIcon: const Icon(Icons.circle_outlined, size: 12, color: Colors.black),
      onChanged: () {
        setState(() {});
        _scheduleEstimate();
      },
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Corners of the inset frame, NW, NE, SE, SW
  List<LatLng>? _frameOutline() {
    final camera = mapController.camera.value;
    if (!mapReady || camera == null) return null;
    final size = camera.size;
    final corners = [
      camera.screenToLatLng(const Offset(frameMargin, frameMargin)),
      camera.screenToLatLng(Offset(size.width - frameMargin, frameMargin)),
      camera.screenToLatLng(Offset(size.width - frameMargin, size.height - frameMargin)),
      camera.screenToLatLng(Offset(frameMargin, size.height - frameMargin)),
    ];
    return corners.contains(null) ? null : corners.nonNulls.toList();
  }

  OfflineArea? _buildArea() {
    if (layers.isEmpty) return null;
    final outline = polygonMode ? List<LatLng>.from(polyPoints) : _frameOutline();
    if (outline == null || outline.length < 3) return null;
    return OfflineArea(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      created: DateTime.now(),
      outline: outline,
      isPolygon: polygonMode,
      layers: MapTileSrc.values.where(layers.contains).toList(),
    );
  }

  void _scheduleEstimate() {
    _debounce?.cancel();
    _estimateSeq++;
    if (!estimating) {
      // May be called from map callbacks mid-build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => estimating = true);
      });
    }
    _debounce = Timer(estimateDelay, _runEstimate);
  }

  Future _runEstimate() async {
    // Only one at a time. A stale run re-triggers below when it finishes.
    if (_estimateInFlight) return;
    _estimateInFlight = true;
    final seq = _estimateSeq;
    final area = _buildArea();
    final result = area == null ? null : await offlineMapService.estimate(area);
    _estimateInFlight = false;
    if (!mounted) return;
    if (seq != _estimateSeq) {
      // Something changed meanwhile. Run again unless the debounce timer is still waiting to.
      if (!(_debounce?.isActive ?? false)) _runEstimate();
      return;
    }
    setState(() {
      estimate = result;
      estimating = false;
    });
  }

  void _onMapTap(LatLng latlng) {
    if (!polygonMode) return;
    setState(() {
      polyEditor.add(polyPoints, latlng);
    });
    _scheduleEstimate();
  }

  Widget _estimateText() {
    if (estimating) {
      return Center(
          child: const SizedBox(height: 20, width: 20, child: CircularProgressIndicator.adaptive(strokeWidth: 2)));
    }
    if (estimate == null) {
      return Text(
          polygonMode && polyPoints.length < 3 ? "offline_maps.draw_hint".tr() : "offline_maps.select_layer".tr(),
          style: const TextStyle(color: Colors.grey));
    }
    final color = estimate!.isTooLarge
        ? Colors.red
        : estimate!.isLarge
            ? Colors.amber
            : Colors.white;
    return Text(
      "${NumberFormat.decimalPattern().format(estimate!.tiles)} ${"offline_maps.tiles".tr()}  ·  "
      "${asReadableSize(estimate!.bytes.toDouble())}",
      style: TextStyle(color: color, fontSize: 16),
    );
  }

  void _confirmDownload() {
    final area = _buildArea();
    final est = estimate;
    if (area == null || est == null || est.isTooLarge) return;

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(est.isLarge ? "offline_maps.large_title".tr() : "offline_maps.confirm_title".tr()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${"offline_maps.tiles".tr()}: ${NumberFormat.decimalPattern().format(est.tiles)}"),
                  Text("${"offline_maps.size".tr()}: ~${asReadableSize(est.bytes.toDouble())}"),
                  const SizedBox(height: 12),
                  if (est.isLarge)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text("offline_maps.large_warning".tr(), style: const TextStyle(color: Colors.amber)),
                    ),
                  Text("offline_maps.throttle_note".tr(), style: const TextStyle(color: Colors.grey)),
                ],
              ),
              actions: [
                TextButton.icon(
                    onPressed: () {
                      offlineMapService.enqueue(area);
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.download, color: Colors.lightGreen),
                    label: Text("offline_maps.download".tr())),
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text("btn.Cancel".tr())),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final planPoints = Provider.of<ActivePlan>(context, listen: false)
        .waypoints
        .values
        .where((e) => !e.ephemeral)
        .expand((e) => e.latlng)
        .toList();
    final center = (myTelemetry.geo ?? defaultGeo).latlng;

    return Scaffold(
      appBar: AppBar(title: Text("offline_maps.new_area".tr())),
      body: Column(
        children: [
          // --- Map
          Expanded(
            child: Stack(
              children: [
                XcMap(
                    controller: mapController,
                    tileSrc: previewLayer,
                    initialCenter: center,
                    initialZoom: 8,
                    initialBounds:
                        planPoints.length > 1 ? padLatLngBounds(LatLngBounds.fromPoints(planPoints), 0.3) : null,
                    rotateGestures: false,
                    tiltGestures: false,
                    onMapReady: () {
                      mapReady = true;
                      _scheduleEstimate();
                    },
                    onCameraChanged: (camera) {
                      if (!polygonMode && mapReady) _scheduleEstimate();
                    },
                    onTap: (latlng, _) => _onMapTap(latlng),
                    shapes: [
                      if (polygonMode && polyPoints.isNotEmpty)
                        ShapeLayer("area", polygons: [
                          MapPolygon(
                              points: polyPoints.toList(),
                              fillColor: Colors.blue.withAlpha(40),
                              borderColor: Colors.blue,
                              borderWidth: 3),
                        ]),
                    ],
                    children: [
                      if (polygonMode) MarkerLayer(markers: polyEditor.edit(mapController)),
                    ]),

                // --- Visible area frame
                if (!polygonMode)
                  IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(frameMargin),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue, width: 3),
                        color: Colors.blue.withAlpha(20),
                      ),
                    ),
                  ),

                // --- Polygon tools
                if (polygonMode)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Card(
                      color: Colors.black54,
                      child: Row(children: [
                        IconButton(
                            tooltip: "offline_maps.undo".tr(),
                            onPressed: polyPoints.isEmpty
                                ? null
                                : () {
                                    setState(() => polyPoints.removeLast());
                                    _scheduleEstimate();
                                  },
                            icon: const Icon(Icons.undo)),
                        IconButton(
                            tooltip: "btn.Clear".tr(),
                            onPressed: polyPoints.isEmpty
                                ? null
                                : () {
                                    setState(() => polyPoints.clear());
                                    _scheduleEstimate();
                                  },
                            icon: const Icon(Icons.clear)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),

          // --- Options
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Area mode
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.crop_free),
                          label: Text("offline_maps.mode_visible".tr())),
                      ButtonSegment(
                          value: true, icon: const Icon(Icons.polyline), label: Text("offline_maps.mode_polygon".tr())),
                    ],
                    selected: {polygonMode},
                    onSelectionChanged: (value) {
                      setState(() {
                        polygonMode = value.first;
                      });
                      _scheduleEstimate();
                    },
                  ),
                  const SizedBox(height: 8),

                  // Layers
                  Wrap(
                    spacing: 8,
                    children: [MapTileSrc.topo, MapTileSrc.sectional, MapTileSrc.satellite]
                        .map((src) => FilterChip(
                              avatar: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(width: 24, height: 24, child: mapTileThumbnails[src])),
                              label: Text("offline_maps.layer.${src.name}".tr()),
                              selected: layers.contains(src),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    layers.add(src);
                                    previewLayer = src;
                                  } else {
                                    layers.remove(src);
                                    if (src == previewLayer && layers.isNotEmpty) previewLayer = layers.last;
                                  }
                                });
                                _scheduleEstimate();
                              },
                            ))
                        .toList(),
                  ),

                  const SizedBox(height: 12),

                  // Estimate + download
                  Row(
                    children: [
                      Expanded(child: _estimateText()),
                      ElevatedButton.icon(
                        onPressed: (!estimating && estimate != null && !estimate!.isTooLarge) ? _confirmDownload : null,
                        icon: const Icon(Icons.download),
                        label: Text("offline_maps.download".tr()),
                      ),
                    ],
                  ),
                  if (estimate?.isTooLarge ?? false)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text("offline_maps.too_large".tr(), style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
