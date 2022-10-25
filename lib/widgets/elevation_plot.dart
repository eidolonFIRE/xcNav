import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart' as Latlng;
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/map_marker.dart';

/// Elevation Sample for a given LatLng coordinate
class ElevSample {
  final Latlng.LatLng latlng;
  final double value;
  final int time;

  ElevSample(this.latlng, this.value, this.time);
}

ui.Image? _arrow;

final Map<String, DrawableRoot> loadedSvgs = {};

class ElevationPlotPainter extends CustomPainter {
  late final Paint _paintGround;
  late final Paint _paintGroundFuture;
  late final Paint _paintElev;
  late final Paint _paintGrid;
  late final Paint _paintVarioTrend;

  final List<Geo> geoData;
  final List<ElevSample?> groundData;

  final double vertGridRes;

  final Waypoint? waypoint;
  final int? waypointETA;

  late final DrawableRoot? svgPin;

  ElevationPlotPainter(this.geoData, this.groundData, this.vertGridRes, {this.waypoint, this.waypointETA}) {
    _paintGround = Paint()
      ..color = Colors.orange.shade800
      ..style = PaintingStyle.fill;

    _paintGroundFuture = Paint()
      ..color = Colors.orange.shade600
      ..style = PaintingStyle.fill;

    _paintElev = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;

    _paintGrid = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    _paintVarioTrend = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;

    if (waypoint != null) {
      void setSvgPin() {
        svgPin = loadedSvgs["pin_master"]!.mergeStyle(DrawableStyle(
            fill: DrawablePaint(ui.PaintingStyle.fill, color: waypoint!.getColor()),
            stroke: DrawablePaint(ui.PaintingStyle.stroke, color: waypoint!.getColor())));
      }

      if (loadedSvgs["pin_master"] == null) {
        rootBundle.loadString("assets/images/pin.svg").then((svgRaw) {
          svg.fromSvgString(svgRaw, "pinsvg").then((value) {
            loadedSvgs["pin_master"] = value;
            setSvgPin();
          });
        });
      } else {
        setSvgPin();
      }
    }

    if (_arrow == null) {
      loadUiImage("./assets/images/red_arrow.png").then((value) => _arrow = value);
    }
  }

  DrawableRoot? getLoadedSvg(String assetName) {
    if (loadedSvgs[assetName] == null) {
      rootBundle.loadString(assetName).then((svgRaw) {
        svg.fromSvgString(svgRaw, assetName).then((value) {
          loadedSvgs[assetName] = value.mergeStyle(const DrawableStyle(
              fill: DrawablePaint(ui.PaintingStyle.fill, color: Colors.white),
              stroke: DrawablePaint(ui.PaintingStyle.stroke, color: Colors.white)));
        });
      });
    }
    return loadedSvgs[assetName];
  }

  Future<ui.Image> loadUiImage(String imageAssetPath) async {
    final ByteData data = await rootBundle.load(imageAssetPath);
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(Uint8List.view(data.buffer), (ui.Image img) {
      return completer.complete(img);
    });
    return completer.future;
  }

  @override
  void paint(Canvas canvas, Size size) {
    debugPrint("PAINT ELEVATION PLOT");
    // --- Common misc.
    // final maxSize = min(size.width, size.height);
    // final Offset center = Offset(size.width / 2, size.height / 2);

    final double maxElev = ((max(
                        geoData.map((e) => e.alt).reduce((a, b) => a > b ? a : b),
                        groundData
                            .where((element) => element != null)
                            .map((e) => e!.value)
                            .reduce((a, b) => a > b ? a : b)) +
                    vertGridRes / 2) /
                vertGridRes)
            .ceil() *
        vertGridRes;

    final double minElev = ((min(
                        geoData
                                .map((e) => e.ground)
                                .where((element) => element != null)
                                .reduce((a, b) => a! < b! ? a : b) ??
                            0,
                        groundData
                                .where((element) => element != null)
                                .reduce((a, b) => a!.value < b!.value ? a : b)
                                ?.value ??
                            0) -
                    vertGridRes / 2) /
                vertGridRes)
            .floor() *
        vertGridRes;
    final double rangeElev = maxElev - minElev;

    double scaleY(double value) {
      return size.height - size.height * (value - minElev) / rangeElev;
    }

    final lastGroundTime = groundData.last?.time ?? 0;
    final rangeTime = geoData.last.time - geoData.first.time + lastGroundTime;

    double scaleX(int value) {
      return size.width * (value - geoData.first.time) / rangeTime;
    }

    Offset scaleOffset(Offset value) {
      return Offset(scaleX(value.dx.round()), scaleY(value.dy));
    }

    // --- Draw Past Ground Level
    {
      final groundPath = Path();
      groundPath.addPolygon(
          geoData
                  .where((element) => element.ground != null)
                  .map((e) => Offset(scaleX(e.time), scaleY(e.ground!.toDouble())))
                  .toList() +
              [Offset(scaleX(geoData.last.time), size.height), Offset(0, size.height)],
          true);
      canvas.drawPath(groundPath, _paintGround);
    }

    // --- Draw Future Ground Level
    {
      final groundPath = Path();
      groundPath.addPolygon(
          groundData
                  .where((element) => element != null)
                  .map((e) => Offset(scaleX(e!.time + geoData.last.time), scaleY(e.value.toDouble())))
                  .toList() +
              [Offset(size.width, size.height), Offset(scaleX(geoData.last.time), size.height)],
          true);

      canvas.drawPath(groundPath, _paintGroundFuture);
    }

    // --- Draw Pilot Elevation Track
    canvas.drawPoints(
        ui.PointMode.polygon, geoData.map((e) => Offset(scaleX(e.time), scaleY(e.alt))).toList(), _paintElev);

    // --- Draw Elevation grid lines
    for (double t = minElev; t <= maxElev; t += vertGridRes) {
      canvas.drawLine(Offset(0, scaleY(t)), Offset(size.width, scaleY(t)), _paintGrid);
      TextSpan span = TextSpan(
          style: const TextStyle(color: Colors.white), text: unitConverters[UnitType.distFine]!(t).toStringAsFixed(0));
      TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(4, scaleY(t)));
    }

    // --- Draw Time grid lines
    for (int t = geoData.first.time +
            ((-geoData.first.time + geoData.last.time) % const Duration(minutes: 5).inMilliseconds);
        t <= rangeTime + geoData.last.time;
        t += const Duration(minutes: 5).inMilliseconds) {
      canvas.drawLine(Offset(scaleX(t), 0), Offset(scaleX(t), 20), _paintGrid);
      canvas.drawLine(Offset(scaleX(t), size.height), Offset(scaleX(t), size.height - 20), _paintGrid);
      // TextSpan span = TextSpan(
      //     style: const TextStyle(color: Colors.white), text: unitConverters[UnitType.distFine]!(t).toStringAsFixed(0));
      // TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
      // tp.layout();
      // tp.paint(canvas, Offset(4, scaleY(t)));
    }

    // --- Draw Vario Trendline
    final base = scaleOffset(Offset(geoData.last.time.toDouble(), geoData.last.alt));
    final slope = Offset(scaleX(1000 + geoData.first.time), -size.height + scaleY(geoData.last.varioSmooth + minElev));
    for (double t = 0; t < size.width - base.dx; t += 20) {
      canvas.drawLine(base + slope * t / slope.dx, base + slope * (t + 10) / slope.dx, _paintVarioTrend);
    }

    // --- Draw Waypoint
    if (waypoint != null && svgPin != null && !waypoint!.isPath) {
      final dx = scaleX((waypointETA! + geoData.last.time).round()) - 20;
      final dy = scaleY(waypoint!.elevation) - 60;
      canvas.translate(dx, dy);
      svgPin!.draw(canvas, Rect.fromCenter(center: Offset.zero, width: 100, height: 100));

      dynamic icon = iconOptions[waypoint?.icon];
      if (waypoint?.icon != null && icon != null) {
        if (icon.runtimeType == IconData) {
          // Render standard icon
          TextPainter textPainter = TextPainter(textDirection: TextDirection.rtl);
          textPainter.text = TextSpan(
              text: String.fromCharCode(icon.codePoint), style: TextStyle(fontSize: 30.0, fontFamily: icon.fontFamily));
          textPainter.layout();
          textPainter.paint(canvas, const Offset(5.0, 5.0));
        } else if (icon.runtimeType == String) {
          // Render svg
          canvas.translate(3, 1);
          getLoadedSvg(icon)?.scaleCanvasToViewBox(canvas, const Size(32, 32));
          getLoadedSvg(icon)?.draw(canvas, Rect.fromCenter(center: Offset.zero, width: 32, height: 32));
          canvas.translate(-3, -1);
        }
      }
      canvas.translate(-dx, -dy);
    }

    // --- Draw Pilot Icon
    if (_arrow != null) {
      canvas.translate(base.dx, base.dy);
      canvas.rotate(slope.direction + pi / 2);
      canvas.drawImageRect(_arrow!, const Rect.fromLTWH(0, 0, 113, 130),
          Rect.fromCenter(center: const Offset(0, 0), width: size.width / 10, height: size.width / 10), Paint());
      canvas.rotate(-slope.direction - pi / 2);
      canvas.translate(-base.dx, -base.dy);
    }

    // --- Draw Vario
    TextPainter tp = TextPainter(
        text: richValue(UnitType.vario, geoData.last.varioSmooth,
            valueStyle: const TextStyle(fontSize: 30),
            unitStyle: const TextStyle(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic)),
        textAlign: TextAlign.right,
        textDirection: TextDirection.ltr);
    tp.layout(minWidth: 60);
    tp.paint(canvas, Offset(scaleX(geoData.last.time) - 20, scaleY(geoData.last.alt) + 20));
  }

  @override
  bool shouldRepaint(ElevationPlotPainter oldDelegate) {
    return oldDelegate.geoData.last.time != geoData.last.time;
    //oldDelegate.maxValue != maxValue;
  }
}
