import 'dart:math';

import 'package:flutter/material.dart';

class DashedLine extends StatefulWidget {
  final Color color;
  final double width;

  const DashedLine(this.color, this.width, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _LineState();
}

class _LineState extends State<DashedLine> with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  late Animation<double> animation;
  late AnimationController controller;

  _LineState();

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
        duration: const Duration(milliseconds: 10000), vsync: this);
    final CurvedAnimation curve =
        CurvedAnimation(parent: controller, curve: Curves.decelerate);
    animation = Tween(begin: 0.0, end: 1.0).animate(curve)
      ..addListener(() {
        setState(() {
          _progress = animation.value;
        });
      });

    controller.forward();
    // ENABEL THIS TO LOOP THE ANIMATION WHILE DEBUGGING
    // controller.addListener(() {
    //   if (controller.isCompleted) {
    //     controller.repeat();
    //   }
    // });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
        painter: LinePainter(_progress, widget.color, widget.width));
  }
}

class LinePainter extends CustomPainter {
  late Paint _paint;
  late double _progress;

  LinePainter(double progress, Color color, double width) {
    _paint = Paint()
      ..color = color
      ..strokeWidth = width;
    _progress = progress;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const int dashWidth = 20;
    const int dashSpace = 8;

    double skew = size.height / size.width;
    Offset end = Offset(size.width * _progress, size.height * _progress);

    double posX = end.dx;
    double posY = end.dy;

    while (posX > 0) {
      // Draw a small line.
      canvas.drawLine(
          Offset(posX, posY),
          Offset(max(0, posX - dashWidth), max(0, posY - dashWidth * skew)),
          _paint);

      // Update the starting X
      posX -= dashWidth + dashSpace;
      posY -= (dashWidth + dashSpace) * skew;
    }
  }

  @override
  bool shouldRepaint(LinePainter oldDelegate) {
    return oldDelegate._progress != _progress;
  }
}
