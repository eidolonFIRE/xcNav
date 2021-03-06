import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:xcnav/providers/weather.dart';

class SoundingPlotWindPainter extends CustomPainter {
  late final Paint _paintVel;
  late final Paint _paintGrid;
  late final Paint _paintBarb;
  late final Paint _paintDanger;

  final Sounding sounding;

  late double? selectedY;
  late double myBaro;

  SoundingPlotWindPainter(this.sounding, this.selectedY, this.myBaro) {
    _paintVel = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    _paintGrid = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    _paintBarb = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.fill;

    _paintDanger = Paint()
      ..color = Colors.red.withAlpha(100)
      ..style = PaintingStyle.fill;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // --- Common misc.
    // final maxSize = min(size.width, size.height);
    // final Offset center = Offset(size.width / 2, size.height / 2);

    /// Top of the graph in meters
    const ceil = 6000;
    double windCeil = max(9, sounding.data.reduce((a, b) => (a.wVel ?? 0) > (b.wVel ?? 0) ? a : b).wVel! + 1);

    double toX(double vel) => vel / windCeil * size.width;

    // --- danger area
    canvas.drawRect(Rect.fromLTWH(toX(8), 0, size.width - toX(8), size.height), _paintDanger);

    // --- Wind Velocity
    canvas.drawPoints(
        PointMode.polygon,
        sounding.data.where((element) => element.wVel != null).map((e) {
          final altMeters = getElevation(e.baroAlt, 1013.25);
          final y = altMeters * size.height / ceil;
          return Offset(toX(e.wVel!), size.height - y);
        }).toList(),
        _paintVel);

    // --- Border
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _paintGrid);

    // --- Selected Isobar
    if (selectedY != null) {
      selectedY = max(0, min(size.height, selectedY!));
      canvas.drawLine(Offset(4, selectedY!), Offset(size.width - 4, selectedY!), _paintGrid);
    }

    // --- My Current Isobar
    final myBaroY =
        max(0, min(size.height, size.height - getElevation(myBaro, 1013.25) * size.height / ceil)).toDouble();
    canvas.drawLine(Offset(4, myBaroY), Offset(size.width - 4, myBaroY), _paintGrid..strokeWidth = 2);
    var path = Path();
    path.addPolygon([Offset(2, myBaroY + 5), Offset(10, myBaroY), Offset(2, myBaroY - 5)], true);
    path.addPolygon(
        [Offset(size.width - 2, myBaroY + 5), Offset(size.width - 10, myBaroY), Offset(size.width - 2, myBaroY - 5)],
        true);
    canvas.drawPath(path, _paintBarb);
  }

  @override
  bool shouldRepaint(SoundingPlotWindPainter oldDelegate) {
    return true;
    //oldDelegate.maxValue != maxValue;
  }
}
