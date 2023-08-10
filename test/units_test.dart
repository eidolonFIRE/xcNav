import 'package:flutter/painting.dart';
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
    expect(printHrMinLexical(const Duration(hours: 1, minutes: 0)), "1 hour");
    expect(printHrMinLexical(const Duration(hours: 0, minutes: 90)), "1 hour 30 minutes");
    expect(printHrMinLexical(const Duration(hours: 5, minutes: 90)), "6 hours 30 minutes");

    expect(printHrMinLexical(const Duration(days: 1, hours: 5, minutes: 90)), "30 hours 30 minutes");
  });

  test("printDoubleSimple", () {
    expect(printDoubleSimple(1.23, decimals: 1), "1.2");
    expect(printDoubleSimple(1, decimals: 1), "1");
    expect(printDoubleSimple(1.00023, decimals: 1), "1");
    expect(printDoubleSimple(1.23456, decimals: 3), "1.235");
    expect(printDoubleSimple(1.00000023456, decimals: 3), "1");
  });

  test("printValue", () {
    // Positive numbers
    expect(printDouble(value: 9.2, digits: 2, decimals: 0, autoDecimalThresh: 10.0), "9.2");
    expect(printDouble(value: 9.2, digits: 2, decimals: 0), "9");

    expect(printDouble(value: 1.0, digits: 2, decimals: 1, autoDecimalThresh: 1.0), "1.0");
    expect(printDouble(value: 0.99, digits: 2, decimals: 1, autoDecimalThresh: 1.0), "0.99");
    expect(printDouble(value: 0.99, digits: 2, decimals: 1), "1.0");

    expect(printDouble(value: 123.0, digits: 3, decimals: 0), "123");
    expect(printDouble(value: 123.7, digits: 3, decimals: 0), "124");
    expect(printDouble(value: 123.3, digits: 3, decimals: 0), "123");
    expect(printDouble(value: 123.3, digits: 5, decimals: 0), "123");

    expect(printDouble(value: 123.3, digits: 2, decimals: 0), "99");
    expect(printDouble(value: 123.3, digits: 2, decimals: 2), "99.99");

    // Negative numbers
    expect(printDouble(value: -1.0, digits: 2, decimals: 1, autoDecimalThresh: 1.0), "-1.0");
    expect(printDouble(value: -0.99, digits: 2, decimals: 1, autoDecimalThresh: 1.0), "-0.99");
    expect(printDouble(value: -0.99, digits: 2, decimals: 1), "-1.0");

    expect(printDouble(value: -123.0, digits: 3, decimals: 0), "-123");
    expect(printDouble(value: -123.7, digits: 3, decimals: 0), "-124");
    expect(printDouble(value: -123.3, digits: 3, decimals: 0), "-123");
    expect(printDouble(value: -123.3, digits: 5, decimals: 0), "-123");

    expect(printDouble(value: -123.3, digits: 2, decimals: 0), "-99");
    expect(printDouble(value: -123.3, digits: 2, decimals: 2), "-99.99");
  });

  test("printValueLexical", () {
    // base
    expect(printDoubleLexical(value: 1.0), "1");
    expect(printDoubleLexical(value: 1.25), "1 and 1 quarter");
    expect(printDoubleLexical(value: 1.5), "1 and a half");
    expect(printDoubleLexical(value: 0.125), "1 eighth");
    expect(printDoubleLexical(value: 1.0), "1");
    expect(printDoubleLexical(value: 1.75), "1 and 3 quarters");
    expect(printDoubleLexical(value: 3 / 8), "3 eighths");

    // Rounding
    expect(printDoubleLexical(value: 0.999999), "1");
    expect(printDoubleLexical(value: 1.25 + 0.01), "1 and 1 quarter");
    expect(printDoubleLexical(value: 1.5 + 0.01), "1 and a half");
    expect(printDoubleLexical(value: 1 / 8 + 0.01), "1 eighth");
    expect(printDoubleLexical(value: 1.0 + 0.01), "1");
    expect(printDoubleLexical(value: 1.75 + 0.01), "1 and 3 quarters");
    expect(printDoubleLexical(value: 3 / 8 + 0.01), "3 eighths");
    expect(printDoubleLexical(value: 1.25 - 0.01), "1 and 1 quarter");
    expect(printDoubleLexical(value: 1.5 - 0.01), "1 and a half");
    expect(printDoubleLexical(value: 1 / 8 - 0.01), "1 eighth");
    expect(printDoubleLexical(value: 1.0 - 0.01), "1");
    expect(printDoubleLexical(value: 1.75 - 0.01), "1 and 3 quarters");
    expect(printDoubleLexical(value: 3 / 8 - 0.01), "3 eighths");

    // threshold
    expect(printDoubleLexical(value: 2.15), "2");
    expect(printDoubleLexical(value: 2.45), "2 and a half");
    expect(printDoubleLexical(value: 12.25), "12");
    expect(printDoubleLexical(value: 12.55), "13");
  });

  test("getUnitStr", () {
    // should be no missing unit strings
    for (final type in UnitType.values) {
      expect(getUnitStr(type) != "", true);
    }
  });

  test("unitConverters", () {
    // should be no missing converters
    for (final type in UnitType.values) {
      expect(unitConverters[type] != null, true);
    }
  });

  test("richValue", () {
    // Speed
    configUnits(speed: DisplayUnitsSpeed.mps);
    expect(richValue(UnitType.speed, 1.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["1.00", "m/s"]);
    configUnits(speed: DisplayUnitsSpeed.kph);
    expect(richValue(UnitType.speed, 1.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["3.60", "kph"]);
    configUnits(speed: DisplayUnitsSpeed.kts);
    expect(richValue(UnitType.speed, 1.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["1.94", "kts"]);
    configUnits(speed: DisplayUnitsSpeed.mph);
    expect(richValue(UnitType.speed, 1.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["2.24", "mph"]);

    // Vario
    configUnits(vario: DisplayUnitsVario.mps);
    expect(richValue(UnitType.vario, 1.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["1.000", "m/s"]);
    configUnits(vario: DisplayUnitsVario.fpm);
    expect(richValue(UnitType.vario, 1.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["196.85", "ft/m"]);

    // Dist
    configUnits(dist: DisplayUnitsDist.metric);
    expect(richValue(UnitType.distFine, 1.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["1.00", "m"]);
    expect(
        richValue(UnitType.distCoarse, 1000.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["1.00", "km"]);
    configUnits(dist: DisplayUnitsDist.imperial);
    expect(richValue(UnitType.distFine, 1.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["3.28", "ft"]);
    expect(
        richValue(UnitType.distCoarse, 1000.0, decimals: 2, autoDecimalThresh: null)
            .children!
            .map((InlineSpan e) => e.toPlainText())
            .toList(),
        ["0.62", "mi"]);

    // Fuel
    configUnits(fuel: DisplayUnitsFuel.liter);
    expect(richValue(UnitType.fuel, 1.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["1.00", "L"]);
    configUnits(fuel: DisplayUnitsFuel.gal);
    expect(richValue(UnitType.fuel, 1.0, decimals: 2).children!.map((InlineSpan e) => e.toPlainText()).toList(),
        ["0.26", "gal"]);
  });
}
