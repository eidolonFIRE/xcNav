import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/map_service.dart';

void main() {
  test("asReadableSize", () {
    expect(asReadableSize(1), "1 B");
    expect(asReadableSize(8), "8 B");
    expect(asReadableSize(10), "10 B");

    expect(asReadableSize(80), "0.1 kB");
    expect(asReadableSize(100), "0.1 kB");
    expect(asReadableSize(800), "0.8 kB");

    expect(asReadableSize(1000), "1 kB");
    expect(asReadableSize(8000), "7.8 kB");

    expect(asReadableSize(10000), "9.8 kB");
    expect(asReadableSize(80000), "0.1 MB");

    expect(asReadableSize(100000), "0.1 MB");
    expect(asReadableSize(800000), "0.8 MB");

    expect(asReadableSize(1000000), "1 MB");
    expect(asReadableSize(8000000), "7.6 MB");

    expect(asReadableSize(10000000), "9.5 MB");
    expect(asReadableSize(80000000), "0.1 GB");

    expect(asReadableSize(100000000), "0.1 GB");
    expect(asReadableSize(800000000), "0.7 GB");

    expect(asReadableSize(1000000000), "0.9 GB");
    expect(asReadableSize(8000000000), "7.5 GB");
  });
}
