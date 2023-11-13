import 'dart:math';
import 'package:dart_numerics/dart_numerics.dart';
import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

ui.Image? _arrow;

class WindVectorPlotPainter extends CustomPainter {
  late final Paint _craftPaint;
  late final Paint _windPaint;
  late final Paint _collectivePaint;

  final Offset wind;
  final Offset craft;
  final Offset collective;

  WindVectorPlotPainter(
      {required double strokeWidth, required this.wind, required this.craft, required this.collective}) {
    _craftPaint = Paint()
      ..color = Colors.red
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.fill;

    _collectivePaint = Paint()
      ..color = Colors.amber
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1;

    _windPaint = Paint()
      ..color = Colors.blue
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
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

  void drawArrow(Canvas canvas, Offset start, Offset end, Paint paint, double barbSize) {
    final delta = end - start;
    canvas.drawLine(start, end, paint);
    canvas.drawPoints(
        ui.PointMode.polygon,
        [
          end + Offset(cos(delta.direction - pi / 1.2), sin(delta.direction - pi / 1.2)) * barbSize,
          end,
          end + Offset(cos(delta.direction + pi / 1.2), sin(delta.direction + pi / 1.2)) * barbSize,
        ],
        paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final maxSize = min(size.width, size.height) / 2;
    final Offset center = Offset(size.width / 2, size.height * 2 / 3);

    canvas.translate(center.dx, center.dy);
    // canvas.rotate(-(aCenter + wCenter).direction - piOver2);

    // Airspeed
    canvas.drawLine(Offset.zero, craft * maxSize, _craftPaint);

    if (_arrow != null) {
      canvas.translate(craft.dx * maxSize, craft.dy * maxSize);
      canvas.rotate(craft.direction + pi / 2);
      canvas.drawImageRect(_arrow!, const Rect.fromLTWH(0, 0, 113, 130),
          Rect.fromCenter(center: const Offset(0, 0), width: maxSize / 5, height: maxSize / 5), Paint());
      canvas.rotate(-craft.direction - pi / 2);
      canvas.translate(-craft.dx * maxSize, -craft.dy * maxSize);
    }

    // Wind barb
    drawArrow(canvas, Offset.zero, wind * maxSize, _windPaint, 10);

    // Collective
    drawArrow(canvas, Offset.zero, collective * maxSize, _collectivePaint, 20);
  }

  @override
  bool shouldRepaint(WindVectorPlotPainter oldDelegate) {
    return true;
    //oldDelegate.maxValue != maxValue;
  }
}
