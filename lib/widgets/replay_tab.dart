import 'dart:math';

import 'package:flutter/material.dart';

class ReplayStatusField extends StatelessWidget {
  final String label;
  final Widget child;

  const ReplayStatusField(
      {super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: Colors.grey.shade400)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class ReplayTabIcon extends StatelessWidget {
  const ReplayTabIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final double size = iconTheme.size ?? 24;
    final Color color = iconTheme.color ?? Colors.white;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _NavigationTrianglePainter(
            strokeColor: color,
            fillColor: Colors.transparent,
            strokeWidth: max(1.5, size * 0.08)),
      ),
    );
  }
}

class ReplayMapArrow extends StatelessWidget {
  final double size;

  const ReplayMapArrow({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final Color borderColor = Colors.red.shade900;
    final Color fillColor = Colors.redAccent.shade200;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _NavigationTrianglePainter(
            strokeColor: borderColor,
            fillColor: fillColor,
            strokeWidth: size * 0.12),
      ),
    );
  }
}

class _NavigationTrianglePainter extends CustomPainter {
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  const _NavigationTrianglePainter(
      {required this.strokeColor,
      required this.fillColor,
      required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.7)
      ..lineTo(0, size.height)
      ..close();

    if (fillColor.a > 0) {
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _NavigationTrianglePainter oldDelegate) {
    return oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
