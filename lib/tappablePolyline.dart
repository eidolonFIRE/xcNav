import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';
import 'package:positioned_tap_detector_2/positioned_tap_detector_2.dart';

class TappablePolylineMapPlugin extends MapPlugin {
  @override
  bool supportsLayer(LayerOptions options) => options is TappablePolylineLayerOptions;

  @override
  Widget createLayer(LayerOptions options, MapState mapState, Stream<void> stream) {
    return TappablePolylineLayer(options as TappablePolylineLayerOptions, mapState, stream);
  }
}

/// The options allowing tappable polyline tweaks
class TappablePolylineLayerOptions extends PolylineLayerOptions {
  /// The list of [TaggedPolyline] which could be tapped
  @override
  final List<TaggedPolyline> polylines;

  /// The tolerated distance between pointer and user tap to trigger the [onTap] callback
  final double pointerDistanceTolerance;

  /// The callback to call when a polyline was hit by the tap
  void Function(TaggedPolyline, TapPosition tapPosition)? onTap = (TaggedPolyline polyline, TapPosition tapPosition) {};

  /// Callback when polyline has long press
  void Function(TaggedPolyline, TapPosition tapPosition)? onLongPress =
      (TaggedPolyline polyline, TapPosition tapPosition) {};

  /// The ability to render only polylines in current view bounds
  @override
  final bool polylineCulling;

  TappablePolylineLayerOptions(
      {this.polylines = const [],
      rebuild,
      this.onTap,
      this.onLongPress,
      this.pointerDistanceTolerance = 15,
      this.polylineCulling = false})
      : super(rebuild: rebuild, polylineCulling: polylineCulling);
}

/// A polyline with a tag
class TaggedPolyline extends Polyline {
  /// The name of the polyline
  final String? tag;

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

// A widget to render the layer as a FlutterMap.children
class TappablePolylineLayerWidget extends StatelessWidget {
  final TappablePolylineLayerOptions options;

  TappablePolylineLayerWidget({Key? key, required this.options}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mapState = MapState.maybeOf(context)!;
    return TappablePolylineLayer(options, mapState, mapState.onMoved);
  }
}

enum CallType {
  tap,
  longPress,
}

class TappablePolylineLayer extends StatelessWidget {
  /// The options allowing tappable polyline tweaks
  final TappablePolylineLayerOptions polylineOpts;

  /// The flutter_map [MapState]
  final MapState map;

  /// The Stream used by flutter_map to notify us when a redraw is required
  final Stream<void> stream;

  TappablePolylineLayer(this.polylineOpts, this.map, this.stream);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bc) {
        final size = Size(bc.maxWidth, bc.maxHeight);
        return _build(context, size, polylineOpts.onTap, polylineOpts.onLongPress);
      },
    );
  }

  Widget _build(BuildContext context, Size size, Function? onTap, Function? onLongPress) {
    return StreamBuilder<void>(
      stream: stream, // a Stream<void> or null
      builder: (BuildContext context, _) {
        for (var polylineOpt in polylineOpts.polylines) {
          polylineOpt.offsets.clear();

          if (polylineOpts.polylineCulling && !polylineOpt.boundingBox.isOverlapping(map.bounds)) {
            // Skip this polyline as it is not within the current map bounds (i.e not visible on screen)
            continue;
          }

          var i = 0;
          for (var point in polylineOpt.points) {
            var pos = map.project(point);
            pos = pos.multiplyBy(map.getZoomScale(map.zoom, map.zoom)) - map.getPixelOrigin();
            polylineOpt.offsets.add(Offset(pos.x.toDouble(), pos.y.toDouble()));
            if (i > 0 && i < polylineOpt.points.length) {
              polylineOpt.offsets.add(Offset(pos.x.toDouble(), pos.y.toDouble()));
            }
            i++;
          }
        }

        return GestureDetector(
            onDoubleTap: () {
              // For some strange reason i have to add this callback for the onDoubleTapDown callback to be called.
            },
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
                for (final polylineOpt in polylineOpts.polylines)
                  CustomPaint(
                    painter: PolylinePainter(polylineOpt, false),
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
    for (Polyline currentPolyline in polylineOpts.polylines) {
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

        if (height < polylineOpts.pointerDistanceTolerance &&
            lengthDToOriginalSegment < polylineOpts.pointerDistanceTolerance) {
          var minimum = min(height, lengthDToOriginalSegment);

          if (minimum < closest) {
            closest = minimum;
            bestCandidate = currentPolyline as TaggedPolyline;
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
    final latlng = _offsetToLatLng(localPosition, context.size!.width, context.size!.height);
    final tapPosition = TapPosition(globalPosition, localPosition);

    // Forward the onTap call to map.options so that we won't break onTap
    switch (callType) {
      case CallType.tap:
        map.options.onTap?.call(tapPosition, latlng);
        break;
      case CallType.longPress:
        map.options.onLongPress?.call(tapPosition, latlng);
        break;
    }
  }

  // Todo: Remove this method is v2
  @Deprecated('Distance method should no longer be part of public API')
  double distance(Offset point1, Offset point2) {
    return _distance(point1, point2);
  }

  double _distance(Offset point1, Offset point2) {
    var distancex = (point1.dx - point2.dx).abs();
    var distancey = (point1.dy - point2.dy).abs();

    var distance = sqrt((distancex * distancex) + (distancey * distancey));

    return distance;
  }

  LatLng _offsetToLatLng(Offset offset, double width, double height) {
    var localPoint = CustomPoint(offset.dx, offset.dy);
    var localPointCenterDistance = CustomPoint((width / 2) - localPoint.x, (height / 2) - localPoint.y);
    var mapCenter = map.project(map.center);
    var point = mapCenter - localPointCenterDistance;
    return map.unproject(point);
  }
}
