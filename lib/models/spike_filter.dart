import 'dart:math';

/// Remove isolated spikes from a series using a sliding median (Hampel style) filter.
///
/// An item is rejected when its value deviates from the median of its neighborhood (`radius` items on each side,
/// including itself) by more than `threshold`. Real step changes (cliffs) survive because the median follows whichever
/// side of the step holds the majority, but single or paired outliers are dropped.
List<T> rejectSpikes<T>(List<T> items, double Function(T) value, double threshold, {int radius = 2}) {
  if (items.length < 3) return items;

  final values = items.map(value).toList();
  final List<T> retval = [];
  for (int i = 0; i < items.length; i++) {
    // Shrink the window near the ends so it stays centered (odd width). The very first/last item uses its two nearest
    // neighbors instead.
    final r = max(1, min(radius, min(i, values.length - 1 - i)));
    final start = max(0, min(i - r, values.length - (2 * r + 1)));
    final window = values.sublist(start, start + 2 * r + 1)..sort();
    final median = window[r];
    if ((values[i] - median).abs() <= threshold) {
      retval.add(items[i]);
    }
  }
  return retval;
}
