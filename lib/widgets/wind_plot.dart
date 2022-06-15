import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

ui.Image? _arrow;

class WindPlotPainter extends CustomPainter {
  late final Paint _paint;
  final List<double> dataX;
  final List<double> dataY;
  final double maxValue;
  late final Paint _paintGrid;

  late final Offset circleCenter;
  late final double circleRadius;
  late final Paint circlePaint;

  late final Paint _barbPaint;
  late final Paint _mePaint;

  late final bool isActive;

  WindPlotPainter(
      double width, this.dataX, this.dataY, this.maxValue, this.circleCenter, this.circleRadius, this.isActive) {
    _paint = Paint()..color = Colors.red;
    _paint.style = PaintingStyle.fill;

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

    _mePaint = Paint()
      ..color = Colors.red
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
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

    // Paint grid
    const _pad = 0.9;
    canvas.drawLine(
        Offset(size.width * (1 - _pad), size.height / 2), Offset(size.width * _pad, size.height / 2), _paintGrid);
    canvas.drawLine(
        Offset(size.width / 2, size.height * (1 - _pad)), Offset(size.width / 2, size.height * _pad), _paintGrid);

    // Paint Wind fit
    final _circleCenter = circleCenter * maxSize / maxValue + center;
    canvas.drawCircle(_circleCenter, circleRadius * maxSize / maxValue, circlePaint);

    // Paint samples
    for (int i = 0; i < dataX.length; i++) {
      canvas.drawCircle(Offset(dataX[i], dataY[i]) * maxSize / maxValue + center, 3, _paint);
    }

    // Wind barb
    canvas.drawLine(center, _circleCenter, _barbPaint);
    canvas.drawPoints(
        PointMode.polygon,
        [
          _circleCenter +
              Offset(cos(circleCenter.direction - pi / 1.2), sin(circleCenter.direction - pi / 1.2)) *
                  circleCenter.distance *
                  maxSize /
                  maxValue /
                  3,
          _circleCenter,
          _circleCenter +
              Offset(cos(circleCenter.direction + pi / 1.2), sin(circleCenter.direction + pi / 1.2)) *
                  circleCenter.distance *
                  maxSize /
                  maxValue /
                  3,
        ],
        _barbPaint);

    // Last reading (current movement)
    if (isActive) {
      final lastPoint = Offset(dataX.last, dataY.last);
      final lastPointScaled = lastPoint * maxSize / maxValue + center;
      canvas.drawLine(center, lastPointScaled, _mePaint);
      if (_arrow != null) {
        canvas.translate(lastPointScaled.dx, lastPointScaled.dy);
        canvas.rotate(lastPoint.direction + pi / 2);
        canvas.drawImageRect(_arrow!, const Rect.fromLTWH(0, 0, 128, 130),
            Rect.fromCenter(center: const Offset(0, 0), width: maxSize / 3, height: maxSize / 3), Paint());
      }
    }
  }

  @override
  bool shouldRepaint(WindPlotPainter oldDelegate) {
    return true;
    //oldDelegate.maxValue != maxValue;
  }
}
