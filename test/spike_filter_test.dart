import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/models/spike_filter.dart';

void main() {
  double identity(double v) => v;

  test("passes through short lists", () {
    expect(rejectSpikes([1.0, 5000.0], identity, 10), [1.0, 5000.0]);
  });

  test("rejects a single spike", () {
    final values = [500.0, 510.0, 520.0, -32768.0, 530.0, 540.0, 550.0];
    expect(rejectSpikes(values, identity, 300), [500.0, 510.0, 520.0, 530.0, 540.0, 550.0]);
  });

  test("rejects a spike at either end", () {
    expect(rejectSpikes([9000.0, 500.0, 510.0, 520.0], identity, 300), [500.0, 510.0, 520.0]);
    expect(rejectSpikes([500.0, 510.0, 520.0, 9000.0], identity, 300), [500.0, 510.0, 520.0]);
  });

  test("rejects two adjacent spikes", () {
    final values = [500.0, 510.0, 4000.0, 4100.0, 530.0, 540.0, 550.0];
    expect(rejectSpikes(values, identity, 300), [500.0, 510.0, 530.0, 540.0, 550.0]);
  });

  test("keeps a real cliff step", () {
    final values = [100.0, 100.0, 100.0, 100.0, 1100.0, 1100.0, 1100.0, 1100.0];
    expect(rejectSpikes(values, identity, 300), values);
  });

  test("keeps steady climb", () {
    final values = List.generate(20, (i) => 200.0 + i * 250);
    expect(rejectSpikes(values, identity, 300), values);
  });

  test("valid elevation bounds", () {
    expect(isValidElevation(-32768), isFalse);
    expect(isValidElevation(-430), isTrue);
    expect(isValidElevation(0), isTrue);
    expect(isValidElevation(8849), isTrue);
    expect(isValidElevation(20000), isFalse);
  });
}
