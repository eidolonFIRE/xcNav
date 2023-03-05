import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/widgets/chart_log_duration_hist.dart';

void main() {
  testWidgets("nextInterval", ($) async {
    final widget = ChartLogDurationHist(logs: const []);

    // build the buckets
    for (int x = 0; x < 10; x++) {
      widget.totals.add(LogStatHist(widget.nextInterval(widget.totals.length)));
    }

    expect(widget.totals[0].x, const Duration(minutes: 0));
    expect(widget.totals[1].x, const Duration(minutes: 10));
    expect(widget.totals[2].x, const Duration(minutes: 20));
    expect(widget.totals[3].x, const Duration(minutes: 30));
    expect(widget.totals[4].x, const Duration(minutes: 45));
    expect(widget.totals[5].x, const Duration(minutes: 60));
    expect(widget.totals[6].x, const Duration(minutes: 75));
    expect(widget.totals[7].x, const Duration(minutes: 90));
    expect(widget.totals[8].x, const Duration(minutes: 105));
  });

  testWidgets("toIndex", ($) async {
    final widget = ChartLogDurationHist(logs: const []);

    // build the buckets
    for (int x = 0; x < 10; x++) {
      widget.totals.add(LogStatHist(widget.nextInterval(widget.totals.length)));
    }

    expect(widget.toIndex(const Duration(minutes: 0)), 0);
    expect(widget.toIndex(const Duration(minutes: 2)), 0);
    expect(widget.toIndex(const Duration(minutes: 6)), 1);
    expect(widget.toIndex(const Duration(minutes: 10)), 1);
    expect(widget.toIndex(const Duration(minutes: 11)), 1);
    expect(widget.toIndex(const Duration(minutes: 14)), 1);
    expect(widget.toIndex(const Duration(minutes: 16)), 2);
    expect(widget.toIndex(const Duration(minutes: 20)), 2);
    expect(widget.toIndex(const Duration(minutes: 61)), 5);
    expect(widget.toIndex(const Duration(minutes: 59)), 5);
  });

  testWidgets("buildTotals", ($) async {
    final widget = ChartLogDurationHist(logs: const []);

    // build the buckets
    widget.buildTotals([const Duration(), const Duration(minutes: 15), const Duration(minutes: 101)]);
    expect(widget.totals[widget.toIndex(const Duration())].y, 1);
    expect(widget.totals[widget.toIndex(const Duration(minutes: 15))].y, 1);
    expect(widget.totals[widget.toIndex(const Duration(minutes: 101))].y, 1);

    expect(widget.totals[0].y, 1);
    expect(widget.totals[2].y, 1);
    expect(widget.totals[8].y, 1);

    expect(widget.totals.length, 9);
  });

  testWidgets("endcap", ($) async {
    final widget = ChartLogDurationHist(logs: const []);

    // build the buckets
    widget.buildTotals([const Duration(), const Duration(minutes: 20), const Duration(minutes: 20)]);
    expect(widget.totals.length, 3);
  });
}
