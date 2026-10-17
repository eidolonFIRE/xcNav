import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/views/map/map_markers.dart';
import 'package:xcnav/views/map/xc_map.dart';

/// Edit a path (or polygon) on the map with drag handles.
///
/// - Drag a corner to move it, long press to remove it.
/// - Drag the handle half way between two corners to add a corner there.
class MapPolyEditor {
  final List<LatLng> points;
  final Widget pointIcon;
  final Size pointIconSize;
  final Widget? intermediateIcon;
  final Size intermediateIconSize;

  /// Polygon: also edit the closing edge from the last point back to the first
  final bool closed;
  final VoidCallback? onChanged;

  /// Stable identity for each point, so a handle keeps its gesture while points are added before it
  final List<int> _ids = [];
  int _nextId = 0;

  int? _dragIndex;
  final _tracker = MapDragTracker();

  MapPolyEditor({
    required this.points,
    required this.pointIcon,
    this.pointIconSize = const Size(30, 30),
    this.intermediateIcon,
    this.intermediateIconSize = const Size(30, 30),
    this.closed = false,
    this.onChanged,
  });

  void _syncIds() {
    while (_ids.length < points.length) {
      _ids.add(_nextId++);
    }
    if (_ids.length > points.length) _ids.removeRange(points.length, _ids.length);
  }

  void add(List<LatLng> pointsList, LatLng point) {
    pointsList.add(point);
    onChanged?.call();
  }

  void remove(int index) {
    _syncIds();
    points.removeAt(index);
    _ids.removeAt(index);
    onChanged?.call();
  }

  void _insert(int index, LatLng point) {
    _syncIds();
    points.insert(index, point);
    _ids.insert(index, _nextId++);
  }

  void _dragStart(XcMapController controller, int index, Offset global) {
    _dragIndex = index;
    _tracker.start(controller, global, points[index]);
  }

  void _dragUpdate(XcMapController controller, Offset global) {
    final index = _dragIndex;
    if (index == null || index >= points.length) return;
    final latlng = _tracker.update(controller, global);
    if (latlng == null) return;
    points[index] = latlng;
    onChanged?.call();
  }

  void _dragEnd() {
    _dragIndex = null;
    _tracker.end();
  }

  /// Handles for the current points. Rebuild them whenever [onChanged] fires.
  List<MapMarker> edit(XcMapController controller) {
    _syncIds();
    final List<MapMarker> markers = [];

    for (int c = 0; c < points.length; c++) {
      final index = c;
      markers.add(MapMarker(
        key: ValueKey(("point", _ids[c])),
        point: points[c],
        width: pointIconSize.width,
        height: pointIconSize.height,
        child: MapDragHandle(
          onDragStart: (global) => _dragStart(controller, index, global),
          onDragUpdate: (global) => _dragUpdate(controller, global),
          onDragEnd: _dragEnd,
          onLongPress: () => remove(index),
          child: pointIcon,
        ),
      ));
    }

    if (intermediateIcon != null) {
      final edges = closed && points.length > 2 ? points.length : points.length - 1;
      for (int c = 0; c < edges; c++) {
        final a = points[c];
        final b = points[(c + 1) % points.length];
        final mid = LatLng((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2);
        markers.add(MapMarker(
          key: ValueKey(("mid", _ids[c])),
          point: mid,
          width: intermediateIconSize.width,
          height: intermediateIconSize.height,
          child: MapDragHandle(
            onDragStart: (global) {
              _insert(c + 1, mid);
              _dragStart(controller, c + 1, global);
              onChanged?.call();
            },
            onDragUpdate: (global) => _dragUpdate(controller, global),
            onDragEnd: _dragEnd,
            child: intermediateIcon!,
          ),
        ));
      }
    }

    return markers;
  }
}
