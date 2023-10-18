import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';

class TaggedPolyline extends Polyline {
  /// The name of the polyline
  final String? tag;

  final List<Offset> offsets = [];

  TaggedPolyline(
      {required points,
      strokeWidth = 1.0,
      color = const Color(0xFF00FF00),
      borderStrokeWidth = 0.0,
      borderColor = const Color(0xFFFFFF00),
      gradientColors,
      colorsStop,
      isDotted = false,
      this.tag})
      : super(
            points: points,
            strokeWidth: strokeWidth,
            color: color,
            borderStrokeWidth: borderStrokeWidth,
            borderColor: borderColor,
            gradientColors: gradientColors,
            colorsStop: colorsStop,
            isDotted: isDotted);
}

enum CallType {
  tap,
  longPress,
}

/// The options allowing tappable polyline tweaks
class TappablePolylineLayer extends PolylineLayer {
  /// The list of [TaggedPolyline] which could be tapped
  @override
  // ignore: overridden_fields
  final List<TaggedPolyline> polylines;

  /// The tolerated distance between pointer and user tap to trigger the [onTap] callback
  final double pointerDistanceTolerance;

  /// The callback to call when a polyline was hit by the tap
  final void Function(TaggedPolyline, TapPosition tapPosition)? onTap;

  /// Callback when polyline has long press
  final void Function(TaggedPolyline, TapPosition tapPosition)? onLongPress;

  const TappablePolylineLayer({
    Key? key,
    this.polylines = const [],
    this.onTap,
    this.onLongPress,
    this.pointerDistanceTolerance = 15,
    polylineCulling = false,
  }) : super(key: key, polylines: polylines, polylineCulling: polylineCulling);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bc) {
        final size = Size(bc.maxWidth, bc.maxHeight);
        final mapState = FlutterMapState.maybeOf(context)!;
        for (var polylineOpt in polylines) {
          polylineOpt.offsets.clear();

          if (polylineCulling && !polylineOpt.boundingBox.isOverlapping(mapState.bounds)) {
            // Skip this polyline as it is not within the current map bounds (i.e not visible on screen)
            continue;
          }

          var i = 0;
          for (var point in polylineOpt.points) {
            var pos = mapState.project(point);
            pos = pos.multiplyBy(mapState.getZoomScale(mapState.zoom, mapState.zoom)) - mapState.pixelOrigin;
            polylineOpt.offsets.add(Offset(pos.x.toDouble(), pos.y.toDouble()));
            if (i > 0 && i < polylineOpt.points.length) {
              polylineOpt.offsets.add(Offset(pos.x.toDouble(), pos.y.toDouble()));
            }
            i++;
          }
        }

        return GestureDetector(
            onLongPressEnd: ((details) {
              if (!_handlePolylineTap(details.localPosition, details.globalPosition, onLongPress)) {
                // Only forward the call on to the map if we didn't hit a single polyline
                _forwardCallToMapOptions(CallType.longPress, details.localPosition, details.globalPosition, context);
              }
            }),
            onTapUp: (TapUpDetails details) {
              if (!_handlePolylineTap(details.localPosition, details.globalPosition, onTap)) {
                // Only forward the call on to the map if we didn't hit a single polyline
                _forwardCallToMapOptions(CallType.tap, details.localPosition, details.globalPosition, context);
              }
            },
            child: Stack(
              children: [
                CustomPaint(
                  painter: PolylinePainter(polylines, false, mapState),
                  size: size,
                ),
              ],
            ));
      },
    );
  }

  bool _handlePolylineTap(Offset localPosition, Offset globalPosition, Function? onHit) {
    // We might hit close to multiple polylines. We will therefore keep a reference to these in this map.
    TaggedPolyline? bestCandidate;
    double closest = double.infinity;

    bool atLeastOneHit = false;

    // Calculating taps in between points on the polyline. We
    // iterate over all the segments in the polyline to find any
    // matches with the tapped point within the
    // pointerDistanceTolerance.
    for (final currentPolyline in polylines) {
      for (var j = 0; j < currentPolyline.offsets.length - 1; j++) {
        // We consider the points point1, point2 and tap points in a triangle
        var point1 = currentPolyline.offsets[j];
        var point2 = currentPolyline.offsets[j + 1];
        var tap = localPosition;

        // To determine if we have tapped in between two po ints, we
        // calculate the length from the tapped point to the line
        // created by point1, point2. If this distance is shorter
        // than the specified threshold, we have detected a tap
        // between two points.
        //
        // We start by calculating the length of all the sides using pythagoras.
        var a = _distance(point1, point2);
        var b = _distance(point1, tap);
        var c = _distance(point2, tap);

        // To find the height when we only know the lengths of the sides, we can use Herons formula to get the Area.
        var semiPerimeter = (a + b + c) / 2.0;
        var triangleArea = sqrt(semiPerimeter * (semiPerimeter - a) * (semiPerimeter - b) * (semiPerimeter - c));

        // We can then finally calculate the length from the tapped point onto the line created by point1, point2.
        // Area of triangles is half the area of a rectangle
        // area = 1/2 base * height -> height = (2 * area) / base
        var height = (2 * triangleArea) / a;

        // We're not there yet - We need to satisfy the edge case
        // where the perpendicular line from the tapped point onto
        // the line created by point1, point2 (called point D) is
        // outside of the segment point1, point2. We need
        // to check if the length from D to the original segment
        // (point1, point2) is less than the threshold.

        var hypotenus = max(b, c);
        var newTriangleBase = sqrt((hypotenus * hypotenus) - (height * height));
        var lengthDToOriginalSegment = newTriangleBase - a;

        if (height < pointerDistanceTolerance && lengthDToOriginalSegment < pointerDistanceTolerance) {
          var minimum = min(height, lengthDToOriginalSegment);

          if (minimum < closest) {
            closest = minimum;
            bestCandidate = currentPolyline;
          }
        }
      }
    }

    if (bestCandidate != null) {
      // We look up in the map of distances to the tap, and choose the shortest one.
      onHit?.call(bestCandidate, TapPosition(globalPosition, localPosition));
      atLeastOneHit = true;
    }
    return atLeastOneHit;
  }

  void _forwardCallToMapOptions(CallType callType, Offset localPosition, Offset globalPosition, BuildContext context) {
    final mapState = FlutterMapState.maybeOf(context)!;
    final latlng = _offsetToLatLng(mapState, localPosition, context.size!.width, context.size!.height);
    final tapPosition = TapPosition(globalPosition, localPosition);

    // Forward the onTap call to map.options so that we won't break onTap
    switch (callType) {
      case CallType.tap:
        mapState.options.onTap?.call(tapPosition, latlng);
        break;
      case CallType.longPress:
        mapState.options.onLongPress?.call(tapPosition, latlng);
        break;
    }
  }

  double _distance(Offset point1, Offset point2) {
    var distancex = (point1.dx - point2.dx).abs();
    var distancey = (point1.dy - point2.dy).abs();

    var distance = sqrt((distancex * distancex) + (distancey * distancey));

    return distance;
  }

  LatLng _offsetToLatLng(FlutterMapState mapState, Offset offset, double width, double height) {
    var localPoint = CustomPoint(offset.dx, offset.dy);
    var localPointCenterDistance = CustomPoint((width / 2) - localPoint.x, (height / 2) - localPoint.y);
    var mapCenter = mapState.project(mapState.center);
    var point = mapCenter - localPointCenterDistance;
    return mapState.unproject(point);
  }
}
