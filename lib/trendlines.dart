import 'dart:math';

import 'package:collection/collection.dart';

class TrendlineResult {
  final List<Point<double>> points;
  final double errorTotal;
  final double slope;
  final double offset;

  TrendlineResult(this.points, this.errorTotal, this.slope, this.offset);
}

TrendlineResult getLinearTrendline(List<Point<double>> values) {
  // slope = (n(sum(x*y) - sum(x)sum(y)))/(n*sum(x2) - sum(x)2)
  double n = values.length.toDouble();

  double sumX = 0;
  double sumY = 0;
  double sumX2 = 0;
  double sumXY = 0;

  for (final e in values) {
    final x = e.x;
    sumX += x;
    sumY += e.y;
    sumXY += x * e.y;
    sumX2 += x * x;
  }

  double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
  if (slope.isNaN || slope.isInfinite) {
    slope = 0;
  }
  // offest = (sum(y) - slope*sum(x)) / n
  double offset = (sumY - slope * sumX) / n;

  double error = values.map((e) => e.y - (slope * e.x + offset)).map((e) => e.abs()).sum;

  // y = slope * x + offset
  return TrendlineResult([
    Point<double>(values.first.x, slope * values.first.x + offset),
    Point<double>(values.last.x, slope * values.last.x + offset)
  ], error, slope, offset);
}

TrendlineResult getLinearTrendlineTuned(
    {required List<Point<double>> values, required double outlierThresh, int iterations = 3}) {
  TrendlineResult result = getLinearTrendline(values);
  List<Point<double>> copy = values.toList();
  for (int t = 0; t < iterations; t++) {
    copy = copy.where((e) => (e.y - (result.slope * e.x + result.offset)).abs() < outlierThresh).toList();
    if (copy.length < 2) {
      break;
    }
    result = getLinearTrendline(copy);
  }

  return result;
}
