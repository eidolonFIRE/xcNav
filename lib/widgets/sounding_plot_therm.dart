import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:xcnav/providers/weather.dart';

class SoundingPlotThermPainter extends CustomPainter {
  late final Paint _paintTmp;
  late final Paint _paintDpt;
  late final Paint _paintGrid;
  late final Paint _paintThermLines;
  late final Paint _paintDryAd;
  late final Paint _paintWetAd;
  late final Paint _paintBarb;
  final Sounding sounding;

  late double? selectedY;
  late double myBaro;

  SoundingPlotThermPainter(this.sounding, this.selectedY, this.myBaro) {
    _paintTmp = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    _paintDpt = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    _paintGrid = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    _paintThermLines = Paint()
      ..color = const Color.fromARGB(255, 150, 0, 0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    _paintDryAd = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    _paintWetAd = Paint()
      ..color = Colors.blue.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    _paintBarb = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.fill
      ..strokeWidth = 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // --- Common misc.
    // final maxSize = min(size.width, size.height);
    // final Offset center = Offset(size.width / 2, size.height / 2);

    const skew = 0.2;

    /// Top of the graph in meters
    const ceil = 6000;
    final double maxTmp = sounding.data.reduce((a, b) => (a.tmp ?? 0) > (b.tmp ?? 0) ? a : b).tmp!;
    final double minTmp = sounding.data.reduce((a, b) => (a.tmp ?? 0) < (b.tmp ?? 0) ? a : b).tmp!;
    final thermCeil = max(20, ((maxTmp + 10) / 20).ceil() * 20);
    final thermFloor = min(0, (minTmp / 20).floor() * 20);
    // final thermFloor = minTmp;

    double toX(double temp) => (temp - thermFloor) / (thermCeil - thermFloor) * size.width;

    // --- Isotherms
    const numThermLines = 8;
    for (int t = 0; t < numThermLines; t++) {
      canvas.drawLine(Offset(size.width * t / numThermLines, size.height),
          Offset(size.width * t / numThermLines + skew * size.height, 0), _paintThermLines);
    }

    // --- Dry Adiabats
    for (int t = 1; t <= numThermLines; t++) {
      List<Offset> _points = [];
      for (double elev = 0; elev <= ceil; elev += ceil / 10) {
        final y = elev / ceil * size.height;
        final temp = dryLapse(
            pressureFromElevation(elev, 1013.25), thermFloor + (thermCeil - thermFloor) / numThermLines * t, 1013.25);
        final x = toX(temp);
        _points.add(Offset(x + skew * y, size.height - y));
      }
      canvas.drawPoints(PointMode.polygon, _points, _paintDryAd);
    }

    // --- Wet Adiabats
    for (int t = 1; t <= numThermLines; t++) {
      List<Offset> _points = [];
      double prevTemp = thermFloor + (thermCeil - thermFloor) / numThermLines * t + celsiusToK;
      double prevP = 1013.25;
      for (double elev = 0; elev <= ceil; elev += ceil / 10) {
        final y = elev / ceil * size.height;
        final p = pressureFromElevation(elev, 1013.25);
        final newTemp = prevTemp + (p - prevP) * moistGradientT(p, prevTemp);

        final x = toX(newTemp - celsiusToK);

        _points.add(Offset(x + skew * y, size.height - y));
        prevP = p;
        prevTemp = newTemp;
      }
      canvas.drawPoints(PointMode.polygon, _points, _paintWetAd);
    }

    // --- Temperature
    canvas.drawPoints(
        PointMode.polygon,
        sounding.data.where((element) => element.tmp != null).map((e) {
          final altMeters = getElevation(e.baroAlt, 1013.25);
          final y = altMeters * size.height / ceil;
          final x = (e.tmp! - thermFloor) / (thermCeil - thermFloor) * size.width;

          return Offset(x + skew * y, size.height - y);
        }).toList(),
        _paintTmp);

    // --- Dewpoint
    canvas.drawPoints(
        PointMode.polygon,
        sounding.data.where((element) => element.dpt != null).map((e) {
          final altMeters = getElevation(e.baroAlt, 1013.25);
          final y = altMeters * size.height / ceil;
          final tmp = e.dpt!;
          final x = (tmp - thermFloor) / (thermCeil - thermFloor) * size.width;

          return Offset(x + skew * y, size.height - y);
        }).toList(),
        _paintDpt);

    // --- Border
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _paintGrid);

    // --- Selected Isobar
    if (selectedY != null) {
      selectedY = max(0, min(size.height, selectedY!));
      canvas.drawLine(Offset(4, selectedY!), Offset(size.width - 4, selectedY!), _paintGrid);
    }

    final myBaroY =
        max(0, min(size.height, size.height - getElevation(myBaro, 1013.25) * size.height / ceil)).toDouble();
    canvas.drawLine(Offset(4, myBaroY), Offset(size.width - 4, myBaroY), _paintGrid..strokeWidth = 2);
    var _path = Path();
    _path.addPolygon([Offset(2, myBaroY + 5), Offset(10, myBaroY), Offset(2, myBaroY - 5)], true);
    _path.addPolygon(
        [Offset(size.width - 2, myBaroY + 5), Offset(size.width - 10, myBaroY), Offset(size.width - 2, myBaroY - 5)],
        true);
    canvas.drawPath(_path, _paintBarb);
  }

  @override
  bool shouldRepaint(SoundingPlotThermPainter oldDelegate) {
    return true;
    //oldDelegate.maxValue != maxValue;
  }
}
