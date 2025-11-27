import 'dart:math';

import 'package:collection/collection.dart';
import 'package:xcnav/util.dart';

class PeakDetectorResult {
  late final List<TimestampDouble> peaks;
  late final List<TimestampDouble> valleys;

  // PeakDetectorResult(this.peaks, this.valleys);

  PeakDetectorResult.fromValues(List<TimestampDouble> values,
      {int radius = 10, double thresh = 0.3, double? peakThreshold}) {
    peaks = [];
    valleys = [];

    // Slide window to find peaks
    for (int i = 0; i < values.length; i++) {
      final left = max(0, i - radius);
      final right = min(values.length, i + radius + 1);
      final window = values.sublist(left, right).map((e) => e.value);
      final localMax = window.max;
      final localMin = window.min;
      final value = values[i].value;
      if (value == localMax && (value - localMin).abs() > thresh) {
        if (peaks.isEmpty || peaks.last.time < values[left].time) {
          if (peakThreshold == null || values[i].value >= peakThreshold) {
            peaks.add(values[i]);
          }
        }
      } else if (value == localMin && (value - localMax).abs() > thresh) {
        if (valleys.isEmpty || valleys.last.time < values[left].time) {
          valleys.add(values[i]);
        }
      }
    }
  }
}

class PeakStatsResult {
  /// Seconds
  late final double meanPeriod;

  /// Seconds
  late final double sdPeriod;
  late final double meanPeak;
  late final double sdPeak;
  late final double meanValley;
  late final double sdValley;

  PeakStatsResult.fromPeaks(PeakDetectorResult data) {
    final List<int> periods = [];

    periods.addAll(data.peaks.convolve((a, b) => b.time - a.time));
    periods.addAll(data.valleys.convolve((a, b) => b.time - a.time));

    if (periods.isEmpty) {
      meanPeriod = 0;
      sdPeriod = 0;
    } else {
      meanPeriod = periods.average / 1000;
      if (periods.length > 1) {
        sdPeriod = sqrt(periods.map((e) => pow((e.toDouble() / 1000) - meanPeriod, 2)).sum / (periods.length - 1));
      } else {
        sdPeriod = 0;
      }
    }

    if (data.peaks.isEmpty) {
      meanPeak = 0;
      sdPeak = 0;
    } else {
      meanPeak = data.peaks.map((e) => e.value).average;
      if (data.peaks.length > 1) {
        sdPeak = sqrt(data.peaks.map((e) => pow(e.value - meanPeak, 2)).sum / (data.peaks.length - 1));
      } else {
        sdPeak = 0;
      }
    }

    if (data.valleys.isEmpty) {
      meanValley = 0;
      sdValley = 0;
    } else {
      meanValley = data.valleys.map((e) => e.value).average;
      if (data.valleys.length > 1) {
        sdValley = sqrt(data.valleys.map((e) => pow(e.value - meanValley, 2)).sum / (data.valleys.length - 1));
      } else {
        sdValley = 0;
      }
    }
  }
}
