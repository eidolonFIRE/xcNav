import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/util.dart';

void main() {
  test("basic", (() {
    expect(parseAsString("value"), "value");
    expect(parseAsString(123), "123");
    expect(parseAsString("123.45"), "123.45");
    expect(parseAsString(true), "true");
    expect(parseAsString(null), null);
  }));
}
