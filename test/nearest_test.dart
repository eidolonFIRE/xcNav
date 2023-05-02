import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/util.dart';

void main() {
  test("bisect", () {
    final a = <double>[10, 20, 30, 40];

    expect(nearestIndex(a, 9), 0);
    expect(nearestIndex(a, 10), 0);
    expect(nearestIndex(a, 11), 0);

    expect(nearestIndex(a, 15), 1);
    expect(nearestIndex(a, 18), 1);
    expect(nearestIndex(a, 20), 1);
    expect(nearestIndex(a, 22), 1);

    expect(nearestIndex(a, 28), 2);
    expect(nearestIndex(a, 30), 2);
    expect(nearestIndex(a, 32), 2);

    expect(nearestIndex(a, 38), 3);
    expect(nearestIndex(a, 40), 3);
    expect(nearestIndex(a, 41), 3);
  });
}
