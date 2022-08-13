import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/units.dart';

void main() {
  // Common Setup
  // setUpAll(() {

  // });

  test("printHrMinLexical", () {
    expect(printHrMinLexical(const Duration(hours: 2, minutes: 10)), "2 hours 10 minutes");
    expect(printHrMinLexical(const Duration(hours: 1, minutes: 10)), "1 hour 10 minutes");
    expect(printHrMinLexical(const Duration(hours: 0, minutes: 10)), "10 minutes");
    expect(printHrMinLexical(const Duration(hours: 0, minutes: 0)), "0 minutes");
    expect(printHrMinLexical(const Duration(hours: 0, minutes: 1)), "1 minute");
    expect(printHrMinLexical(const Duration(hours: 0, minutes: 0)), "0 minutes");
    expect(printHrMinLexical(const Duration(hours: 1, minutes: 0)), "1 hour 0 minutes");
    expect(printHrMinLexical(const Duration(hours: 0, minutes: 90)), "1 hour 30 minutes");
    expect(printHrMinLexical(const Duration(hours: 5, minutes: 90)), "6 hours 30 minutes");

    expect(printHrMinLexical(const Duration(days: 1, hours: 5, minutes: 90)), "30 hours 30 minutes");
  });

  test("printValue", () {
    // Positive numbers
    expect(printValue(value: 1.0, digits: 2, decimals: 1, autoDecimalThresh: 1.0), "1.0");
    expect(printValue(value: 0.99, digits: 2, decimals: 1, autoDecimalThresh: 1.0), "0.99");
    expect(printValue(value: 0.99, digits: 2, decimals: 1), "1.0");

    expect(printValue(value: 123.0, digits: 3, decimals: 0), "123");
    expect(printValue(value: 123.7, digits: 3, decimals: 0), "124");
    expect(printValue(value: 123.3, digits: 3, decimals: 0), "123");
    expect(printValue(value: 123.3, digits: 5, decimals: 0), "123");

    expect(printValue(value: 123.3, digits: 2, decimals: 0), "99");
    expect(printValue(value: 123.3, digits: 2, decimals: 2), "99.99");

    // Negative numbers
    expect(printValue(value: -1.0, digits: 2, decimals: 1, autoDecimalThresh: 1.0), "-1.0");
    expect(printValue(value: -0.99, digits: 2, decimals: 1, autoDecimalThresh: 1.0), "-0.99");
    expect(printValue(value: -0.99, digits: 2, decimals: 1), "-1.0");

    expect(printValue(value: -123.0, digits: 3, decimals: 0), "-123");
    expect(printValue(value: -123.7, digits: 3, decimals: 0), "-124");
    expect(printValue(value: -123.3, digits: 3, decimals: 0), "-123");
    expect(printValue(value: -123.3, digits: 5, decimals: 0), "-123");

    expect(printValue(value: -123.3, digits: 2, decimals: 0), "-99");
    expect(printValue(value: -123.3, digits: 2, decimals: 2), "-99.99");
  });
}
