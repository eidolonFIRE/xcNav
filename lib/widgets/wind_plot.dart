import 'dart:math';
import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

ui.Image? _arrow;

class WindPlotPainter extends CustomPainter {
  late final Paint _paintSample;
  late final Paint _paintSampleTail;
  final List<double> dataX;
  final List<double> dataY;
  final double maxValue;
  late final Paint _paintGrid;

  late final Offset circleCenter;
  late final double circleRadius;
  late final Paint circlePaint;

  late final bool northlock;

  late final Paint _barbPaint;

  WindPlotPainter(
      double width, this.dataX, this.dataY, this.maxValue, this.circleCenter, this.circleRadius, this.northlock) {
    _paintSample = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    _paintSampleTail = Paint()..strokeWidth = 3;

    _paintGrid = Paint()
      ..color = Colors.grey.shade600
      ..strokeWidth = 1;

    circlePaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    _barbPaint = Paint()
      ..color = Colors.blue
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    if (_arrow == null) {
      loadUiImage("./assets/images/red_arrow.png").then((value) => _arrow = value);
    }
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
    final maxSize = min(size.width, size.height) / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    if (!northlock) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(-atan2(dataY.last, dataX.last) - pi / 2);
      canvas.translate(-size.width / 2, -size.height / 2);
    }

    // Paint grid
    const pad = 0.9;
    canvas.drawLine(
        Offset(size.width * (1 - pad), size.height / 2), Offset(size.width * pad, size.height / 2), _paintGrid);
    canvas.drawLine(
        Offset(size.width / 2, size.height * (1 - pad)), Offset(size.width / 2, size.height * pad), _paintGrid);

    // Paint Wind fit
    final cCenter = circleCenter * maxSize / maxValue + center;
    canvas.drawCircle(cCenter, circleRadius * maxSize / maxValue, circlePaint);

    // Paint samples
    _paintSampleTail.shader = ui.Gradient.radial(center, size.width / 2, [
      Colors.red.withAlpha(0),
      Colors.red.withAlpha(5),
      Colors.red.withAlpha(20),
      Colors.red.withAlpha(50),
      Colors.red.withAlpha(255),
    ], [
      0,
      0.25,
      0.5,
      0.75,
      1
    ]);
    for (int i = 0; i < dataX.length; i++) {
      final pointOffset = Offset(dataX[i], dataY[i]) * maxSize / maxValue + center;
      canvas.drawCircle(pointOffset, 2, _paintSample);
      // canvas.drawLine(pointOffset * 0.5 + center * 0.5, pointOffset, _paintSampleTail);
      canvas.drawLine(center, pointOffset, _paintSampleTail);
    }

    // Wind barb
    canvas.drawLine(center, cCenter, _barbPaint);
    canvas.drawPoints(
        ui.PointMode.polygon,
        [
          cCenter +
              Offset(cos(circleCenter.direction - pi / 1.2), sin(circleCenter.direction - pi / 1.2)) *
                  circleCenter.distance *
                  maxSize /
                  maxValue /
                  3,
          cCenter,
          cCenter +
              Offset(cos(circleCenter.direction + pi / 1.2), sin(circleCenter.direction + pi / 1.2)) *
                  circleCenter.distance *
                  maxSize /
                  maxValue /
                  3,
        ],
        _barbPaint);

    // Last reading (current movement)

    final lastPoint = Offset(dataX.last, dataY.last);
    final lastPointScaled = lastPoint * maxSize / maxValue + center;
    if (_arrow != null) {
      canvas.translate(lastPointScaled.dx, lastPointScaled.dy);
      canvas.rotate(lastPoint.direction + pi / 2);
      canvas.drawImageRect(_arrow!, const Rect.fromLTWH(0, 0, 113, 130),
          Rect.fromCenter(center: const Offset(0, 0), width: maxSize / 3, height: maxSize / 3), Paint());
    }
  }

  @override
  bool shouldRepaint(WindPlotPainter oldDelegate) {
    return true;
    //oldDelegate.maxValue != maxValue;
  }
}
