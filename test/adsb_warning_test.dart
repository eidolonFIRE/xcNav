import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/providers/adsb.dart';

/// Seconds (at 1s ticks) when warnings fire for a plane that stays a threat for `duration` seconds.
List<int> warningTimes(WarningThrottle throttle, int duration, {String id = "A", int start = 0}) {
  final base = DateTime(2026);
  return [
    for (int t = start; t < start + duration; t++)
      if (throttle.shouldWarn(id, base.add(Duration(seconds: t)))) t
  ];
}

void main() {
  test("first few at base rate, then backs off to the cap", () {
    expect(warningTimes(WarningThrottle(), 100), [0, 5, 10, 20, 35, 55, 75, 95]);
  });

  test("intervals", () {
    expect(WarningThrottle.intervalAfter(1), WarningThrottle.baseInterval);
    expect(WarningThrottle.intervalAfter(2), WarningThrottle.baseInterval);
    expect(WarningThrottle.intervalAfter(3), const Duration(seconds: 10));
    expect(WarningThrottle.intervalAfter(4), const Duration(seconds: 15));
    expect(WarningThrottle.intervalAfter(100), WarningThrottle.maxInterval);
  });

  test("planes are paced separately", () {
    final throttle = WarningThrottle();
    final base = DateTime(2026);
    expect(throttle.shouldWarn("A", base), isTrue);
    expect(throttle.shouldWarn("B", base), isTrue);
    expect(throttle.shouldWarn("A", base.add(const Duration(seconds: 1))), isFalse);
  });

  test("starts fresh after the plane stays clear", () {
    final throttle = WarningThrottle();
    warningTimes(throttle, 100);

    // Brief gap keeps the backoff (last warning was at 95, next due at 115)
    expect(warningTimes(throttle, 5, start: 105), []);

    // Long gap resets it
    final restart = 109 + WarningThrottle.resetAfter.inSeconds + 1;
    expect(warningTimes(throttle, 11, start: restart), [restart, restart + 5, restart + 10]);
  });

  test("cleanup forgets planes clear for a while", () {
    final throttle = WarningThrottle();
    final base = DateTime(2026);
    throttle.shouldWarn("A", base);
    throttle.cleanup(base.add(const Duration(seconds: 2)));
    expect(throttle.shouldWarn("A", base.add(const Duration(seconds: 3))), isFalse);
    throttle.cleanup(base.add(WarningThrottle.resetAfter + const Duration(seconds: 12)));
    expect(throttle.shouldWarn("A", base.add(WarningThrottle.resetAfter + const Duration(seconds: 12))), isTrue);
  });
}
