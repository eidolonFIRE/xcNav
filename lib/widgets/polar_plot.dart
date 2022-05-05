import 'dart:math';
import 'dart:ui';
import 'package:collection/collection.dart';

import 'package:flutter/material.dart';

class PolarPlotPainter extends CustomPainter {
  late Paint _paint;
  late List<double> _data;
  late double _maxValue;

  late Paint _paintGrid;

  PolarPlotPainter(
      Color color, double width, List<double> data, double maxValue) {
    _paint = Paint()
      ..color = color
      ..strokeWidth = width;
    _paint.style = PaintingStyle.fill;
    _data = data;
    _maxValue = maxValue;

    _paintGrid = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;
  }

  Offset calcPoint(double theta, double value) {
    return Offset(
        cos(theta) * (value / _maxValue), sin(theta) * (value / _maxValue));
  }

  @override
  void paint(Canvas canvas, Size size) {
    Path p = Path();
    p.addPolygon(
        _data
            .mapIndexed<Offset>((i, e) =>
                calcPoint(i / _data.length * 2 * pi, e) * size.width / 2 +
                Offset(size.width / 2, size.height / 2))
            .toList(),
        true);
    canvas.drawPath(p, _paint);

    // Paint grid
    canvas.drawLine(Offset(0, size.height / 2),
        Offset(size.width, size.height / 2), _paintGrid);
    canvas.drawLine(Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height), _paintGrid);
  }

  @override
  bool shouldRepaint(PolarPlotPainter oldDelegate) {
    return true;
    //oldDelegate._maxValue != _maxValue;
  }
}
