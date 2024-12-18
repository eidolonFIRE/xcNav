import 'dart:math';

import 'package:flutter/material.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/util.dart';

class GForceSlice {
  final int start;
  final int end;

  GForceSlice(this.start, this.end);
}

class GForceEvent {
  /// Indeces of gForceSamples
  final GForceSlice gForceIndeces;
  final DateTimeRange timeRange;
  final Geo center;

  GForceEvent(this.gForceIndeces, this.timeRange, this.center);
}

List<GForceSlice> getGForceSlices({required List<TimestampDouble> samples, double high = 3, double low = 1.1}) {
  final List<GForceSlice> events = [];

  final reTriggerHigh = max(1.3, (high - 1) * 0.8 + 1);

  for (int t = 0; t < samples.length; t++) {
    // Initial trigger within 50% of
    if (samples[t].value > high || samples[t].value < 0.5) {
      int start = t;
      int end = start;

      // Extend right
      // - each tick over LOW threshold
      int countLow = 0;
      while (end < samples.length - 1 && countLow < 4000) {
        end++;
        // integrate "uninteresting" time
        if (samples[end].value < low && samples[end].value >= 0.95) {
          countLow += samples[end].time - samples[end - 1].time;
        }
        // if within 80% of HIGH, reset counter
        if (samples[end].value > reTriggerHigh || samples[end].value < .9) {
          countLow = (countLow * 0.8).ceil();
        }
      }
      end--;

      // Extend left
      // - don't overlap with previous
      // - each tick over LOW threshold
      countLow = 0;
      while (start > 0 && (events.isEmpty || start > events.last.end) && countLow < 4000) {
        start--;

        // integrate "uninteresting" time
        if (samples[start].value < low && samples[start].value >= 0.95) {
          countLow += samples[start + 1].time - samples[start].time;
        }
        // if within 80% of HIGH, reset counter
        if (samples[start].value > reTriggerHigh || samples[start].value < .9) {
          countLow = (countLow * 0.8).ceil();
        }
      }
      start++;

      if (end > start + 2) {
        events.add(GForceSlice(max(0, start), min(samples.length, end)));

        // Start the next one after this one.
        t = end;
      }
    }
  }

  return events;
}
