import 'dart:math';
import 'dart:ui';
import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:scidart/numdart.dart';

class PolarPlotPainter extends CustomPainter {
  late Paint _paint;
  late Array2d _data;
  late double _maxValue;
  late Paint _paintGrid;
  late bool _stroke;

  PolarPlotPainter(
      Color color, double width, Array2d data, double maxValue, bool stroke) {
    _paint = Paint()
      ..color = color
      ..strokeWidth = width;
    _paint.style = stroke ? PaintingStyle.stroke : PaintingStyle.fill;
    _data = data;
    _maxValue = maxValue;
    _stroke = stroke;
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
    final maxSize = min(size.width, size.height) / 2;

    if (_stroke) {
      Path p = Path();
      p.addPolygon(
          _data
              .map<Offset>((e) =>
                  calcPoint(e[0], e[1]) * maxSize +
                  Offset(size.width / 2, size.height / 2))
              .toList(),
          true);
      canvas.drawPath(p, _paint);
    } else {
      _data.forEach((e) {
        canvas.drawCircle(
            calcPoint(e[0], e[1]) * maxSize +
                Offset(size.width / 2, size.height / 2),
            _paint.strokeWidth,
            _paint);
      });
    }

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
