import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/views/map/xc_map.dart';

/// A Flutter widget pinned to a spot on the map.
class MapMarker {
  final LatLng point;
  final double width;
  final double height;

  /// Where the marker sits relative to [point]. [Alignment.center] centers it on the point,
  /// [Alignment.topCenter] puts it above the point (eg. a pin), [Alignment.centerRight] to the right of it.
  final Alignment alignment;

  /// Turn with the map, for things drawn in the map's frame (eg. a heading arrow).
  /// Otherwise the marker stays upright on screen.
  final bool rotateWithMap;

  final Widget child;
  final Key? key;

  const MapMarker({
    required this.point,
    required this.width,
    required this.height,
    this.alignment = Alignment.center,
    this.rotateWithMap = false,
    required this.child,
    this.key,
  });

  /// Offset from the marker's top left corner to [point]
  Offset get anchor => Offset(width * (1 - alignment.x) / 2, height * (1 - alignment.y) / 2);
}

/// Draws [markers] over an `XcMap` (or `StaticMap`).
///
/// Markers are only built when this layer is. Camera moves just repaint them in their new spots.
class MarkerLayer extends StatelessWidget {
  final List<MapMarker> markers;

  const MarkerLayer({super.key, required this.markers});

  @override
  Widget build(BuildContext context) {
    final controller = XcMapScope.of(context);
    return Flow(
      delegate: _MarkerFlowDelegate(controller.camera, markers),
      children: markers
          .map((m) => SizedBox(key: m.key, width: m.width, height: m.height, child: m.child))
          .toList(),
    );
  }
}

class _MarkerFlowDelegate extends FlowDelegate {
  final ValueListenable<MapCamera?> camera;
  final List<MapMarker> markers;

  _MarkerFlowDelegate(this.camera, this.markers) : super(repaint: camera);

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tight(Size(markers[i].width, markers[i].height));

  @override
  void paintChildren(FlowPaintingContext context) {
    final cam = camera.value;
    if (cam == null) return;
    for (int i = 0; i < context.childCount && i < markers.length; i++) {
      final m = markers[i];
      final p = cam.latLngToScreen(m.point);
      if (p == null) continue;
      // Skip what's off screen
      final reach = max(m.width, m.height);
      if (p.dx < -reach || p.dy < -reach || p.dx > cam.size.width + reach || p.dy > cam.size.height + reach) continue;

      final anchor = m.anchor;
      final transform = Matrix4.translationValues(p.dx, p.dy, 0);
      if (m.rotateWithMap && cam.bearing != 0) transform.rotateZ(-cam.bearingRad);
      transform.translateByDouble(-anchor.dx, -anchor.dy, 0, 1);
      context.paintChild(i, transform: transform);
    }
  }

  @override
  bool shouldRelayout(_MarkerFlowDelegate oldDelegate) => !identical(oldDelegate.markers, markers);

  @override
  bool shouldRepaint(_MarkerFlowDelegate oldDelegate) =>
      !identical(oldDelegate.markers, markers) || oldDelegate.camera != camera;
}

/// Turns pointer positions during a drag into map positions, keeping the spot where the marker was grabbed.
class MapDragTracker {
  Offset? _grab;

  /// [anchor] is where the dragged marker is pinned to the map
  void start(XcMapController controller, Offset globalPosition, LatLng anchor) {
    final local = controller.globalToLocal(globalPosition);
    final anchorScreen = controller.camera.value?.latLngToScreen(anchor);
    _grab = (local != null && anchorScreen != null) ? local - anchorScreen : Offset.zero;
  }

  LatLng? update(XcMapController controller, Offset globalPosition) {
    final local = controller.globalToLocal(globalPosition);
    if (local == null) return null;
    return controller.camera.value?.screenToLatLng(local - (_grab ?? Offset.zero));
  }

  void end() => _grab = null;
}

/// Gesture wrapper for a marker that can be dragged. Reports global pointer positions,
/// see [MapDragTracker] to turn them into map positions.
class MapDragHandle extends StatelessWidget {
  final Widget child;
  final void Function(Offset globalPosition)? onDragStart;
  final void Function(Offset globalPosition)? onDragUpdate;
  final VoidCallback? onDragEnd;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MapDragHandle({
    super.key,
    required this.child,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      onPanStart: onDragStart == null ? null : (details) => onDragStart!(details.globalPosition),
      onPanUpdate: onDragUpdate == null ? null : (details) => onDragUpdate!(details.globalPosition),
      onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
      onPanCancel: onDragEnd,
      child: child,
    );
  }
}
