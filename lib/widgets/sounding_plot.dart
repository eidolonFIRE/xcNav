import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as UI;

import 'package:flutter/services.dart';
import 'package:xcnav/providers/weather.dart';

UI.Image? _arrow;

class SoundingPlotPainter extends CustomPainter {
  late final Paint _paintTmp;
  late final Paint _paintGrid;
  late final Paint _paintThermLines;
  final Sounding sounding;

  SoundingPlotPainter(this.sounding) {
    _paintTmp = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    _paintGrid = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    _paintThermLines = Paint()
      ..color = Colors.red.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
  }

  Future<UI.Image> loadUiImage(String imageAssetPath) async {
    final ByteData data = await rootBundle.load(imageAssetPath);
    final Completer<UI.Image> completer = Completer();
    UI.decodeImageFromList(Uint8List.view(data.buffer), (UI.Image img) {
      return completer.complete(img);
    });
    return completer.future;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // --- Common misc.
    final maxSize = min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);

    const gap = 10.0;
    const skew = 0.2;

    Rect thermArea = Rect.fromLTWH(0, 0, maxSize * 0.6 - gap, maxSize);
    Rect windArea = Rect.fromLTWH(maxSize * 0.6, 0, maxSize * 0.4, maxSize);

    // --- Border
    canvas.drawRect(thermArea, _paintGrid);
    canvas.drawRect(windArea, _paintGrid);

    // --- tempLines
    const numThermLines = 10;
    for (int t = 0; t <= numThermLines; t++) {
      canvas.drawLine(
          Offset(thermArea.width * t / numThermLines, thermArea.height),
          Offset(thermArea.width * t / numThermLines, 0),
          _paintThermLines);
    }

    // --- Temperature
    canvas.drawPoints(
        PointMode.polygon,
        sounding
            .where((element) => element.tmp != null)
            .map((e) => Offset(e.tmp! / 100 * thermArea.width,
                e.baroAlt! / 1000 * thermArea.height))
            .toList(),
        _paintTmp);

    // // Paint Wind fit
    // final _circleCenter = circleCenter * maxSize / maxValue + center;
    // canvas.drawCircle(
    //     _circleCenter, circleRadius * maxSize / maxValue, circlePaint);

    // // Paint samples
    // for (int i = 0; i < dataX.length; i++) {
    //   canvas.drawCircle(
    //       Offset(dataX[i], dataY[i]) * maxSize / maxValue + center, 3, _paint);
    // }

    // // Wind barb
    // canvas.drawLine(center, _circleCenter, _barbPaint);
    // canvas.drawPoints(
    //     PointMode.polygon,
    //     [
    //       _circleCenter +
    //           Offset(cos(circleCenter.direction - pi / 1.2),
    //                   sin(circleCenter.direction - pi / 1.2)) *
    //               circleCenter.distance *
    //               maxSize /
    //               maxValue /
    //               3,
    //       _circleCenter,
    //       _circleCenter +
    //           Offset(cos(circleCenter.direction + pi / 1.2),
    //                   sin(circleCenter.direction + pi / 1.2)) *
    //               circleCenter.distance *
    //               maxSize /
    //               maxValue /
    //               3,
    //     ],
    //     _barbPaint);
  }

  @override
  bool shouldRepaint(SoundingPlotPainter oldDelegate) {
    return true;
    //oldDelegate.maxValue != maxValue;
  }
}
