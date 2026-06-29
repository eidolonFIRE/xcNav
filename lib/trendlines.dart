import 'package:collection/collection.dart';
import 'package:xcnav/util.dart';

class TrendlineResult {
  final List<TimestampValue<double>> points;
  final double errorTotal;
  final double slope;
  final double offset;

  TrendlineResult(this.points, this.errorTotal, this.slope, this.offset);
}

TrendlineResult getLinearTrendline(List<TimestampValue<double>> values) {
  // slope = (n(sum(x*y) - sum(x)sum(y)))/(n*sum(x2) - sum(x)2)
  double n = values.length.toDouble();

  double sumX = 0;
  double sumY = 0;
  double sumX2 = 0;
  double sumXY = 0;

  for (final e in values) {
    final x = e.time.toDouble();
    sumX += x;
    sumY += e.value;
    sumXY += x * e.value;
    sumX2 += x * x;
  }

  double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
  // offest = (sum(y) - slope*sum(x)) / n
  double offset = (sumY - slope * sumX) / n;

  double error = values.map((e) => e.value - (slope * e.time + offset)).map((e) => e.abs()).sum;

  // y = slope * x + offset
  return TrendlineResult([
    TimestampValue<double>(values.first.time, slope * values.first.time.toDouble() + offset),
    TimestampValue<double>(values.last.time, slope * values.last.time.toDouble() + offset)
  ], error, slope, offset);
}

TrendlineResult getLinearTrendlineTuned(
    {required List<TimestampValue<double>> values, required double outlierThresh, int iterations = 3}) {
  TrendlineResult result = getLinearTrendline(values);
  List<TimestampValue<double>> copy = values.toList();
  for (int t = 0; t < iterations; t++) {
    copy = copy.where((e) => (e.value - (result.slope * e.time + result.offset)).abs() < outlierThresh).toList();
    result = getLinearTrendline(copy);
  }

  return result;
}
