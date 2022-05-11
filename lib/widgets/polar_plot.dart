import 'dart:math';
import 'dart:ui';
import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:scidart/numdart.dart';

class PolarPlotPainter extends CustomPainter {
  late Paint _paint;
  late Array2d data;
  late double maxValue;
  late Paint _paintGrid;

  late Offset circleCenter;
  late double circleRadius;
  late final Paint circlePaint;

  PolarPlotPainter(Color color, double width, this.data, this.maxValue,
      this.circleCenter, this.circleRadius) {
    _paint = Paint()..color = color;
    _paint.style = PaintingStyle.fill;

    _paintGrid = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;

    circlePaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
  }

  Offset calcPoint(double theta, double value) {
    return Offset(
        cos(theta) * (value / maxValue), sin(theta) * (value / maxValue));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final maxSize = min(size.width, size.height) / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    // Path p = Path();
    // p.addPolygon(
    //     _data
    //         .map<Offset>((e) =>
    //             calcPoint(e[0], e[1]) * maxSize +
    //             Offset(size.width / 2, size.height / 2))
    //         .toList(),
    //     true);
    // canvas.drawPath(p, _paint);

    data.forEach((e) {
      canvas.drawCircle(
          Offset(e[0], e[1]) * maxSize / maxValue + center, 3, _paint);
    });

    canvas.drawCircle(circleCenter * maxSize / maxValue + center,
        circleRadius * maxSize / maxValue, circlePaint);

    // Paint grid
    canvas.drawLine(Offset(0, size.height / 2),
        Offset(size.width, size.height / 2), _paintGrid);
    canvas.drawLine(Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height), _paintGrid);
  }

  @override
  bool shouldRepaint(PolarPlotPainter oldDelegate) {
    return true;
    //oldDelegate.maxValue != maxValue;
  }
}
