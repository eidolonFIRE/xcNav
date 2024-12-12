import 'dart:math';

class GForceSlice {
  final int start;
  final int end;

  GForceSlice(this.start, this.end);
}

class GForceSample {
  final int time;
  final double value;

  GForceSample(this.time, this.value);
}

List<GForceSlice> getGForceEvents({required List<GForceSample> samples, double high = 3, double low = 1.1}) {
  final List<GForceSlice> events = [];

  for (int t = 0; t < samples.length; t++) {
    // Initial trigger within 50% of
    if (samples[t].value > high) {
      int start = t;
      int end = start;

      // Extend right
      // - each tick over LOW threshold
      int countLow = 0;
      while (end < samples.length - 1 && countLow < 5000) {
        end++;
        // integrate "uninteresting" time
        if (samples[end].value < low && samples[end].value >= 0.95) {
          countLow += samples[end].time - samples[end - 1].time;
        }
        // if within 80% of HIGH, reset counter
        if (samples[end].value > (high - 1) * 0.8 + 1) {
          countLow = 0;
        }
      }

      // Extend left
      // - don't overlap with previous
      // - each tick over LOW threshold
      countLow = 0;
      while (start > 0 && (events.isEmpty || start > events.last.end) && countLow < 5000) {
        start--;

        // integrate "uninteresting" time
        if (samples[start].value < low && samples[start].value >= 0.95) {
          countLow += samples[start + 1].time - samples[start].time;
        }
        // if within 80% of HIGH, reset counter
        if (samples[start].value > (high - 1) * 0.8 + 1) {
          countLow = 0;
        }
      }

      if (end > start + 1) {
        events.add(GForceSlice(max(0, start), min(samples.length, end)));

        // Start the next one after this one.
        t += end;
      }
    }
  }

  return events;
}
