import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:xcnav/models/flight_log.dart';

typedef LogFilter = bool Function(FlightLog log);

DateTime? logFilterDateStart;
DateTime? logFilterDateEnd;
String? logFilterGearSearch;

Future<List<LogFilter>?> editLogFilters(BuildContext context) async {
  return showDialog<List<LogFilter>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Date Range".tr()),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    logFilterDateStart == null
                        ? Text(
                            "start".tr(),
                            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                          )
                        : Text(logFilterDateStart.toString().substring(0, 10)),
                    IconButton(
                        onPressed: () {
                          showDialog(
                              context: context,
                              builder: (context) => DatePickerDialog(
                                    initialDate: logFilterDateStart ?? logFilterDateEnd ?? DateTime.now(),
                                    firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
                                    lastDate: logFilterDateEnd ?? DateTime.now().add(const Duration(days: 1)),
                                  )).then((value) {
                            setState(
                              () {
                                logFilterDateStart = value;
                              },
                            );
                          });
                        },
                        icon: const Icon(Icons.calendar_month, color: Colors.lightBlue)),
                    const Text("  "),
                    logFilterDateEnd == null
                        ? Text(
                            "end".tr(),
                            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                          )
                        : Text(logFilterDateEnd.toString().substring(0, 10)),
                    IconButton(
                        onPressed: () {
                          showDialog(
                              context: context,
                              builder: (context) => DatePickerDialog(
                                    initialDate: logFilterDateEnd ?? logFilterDateStart ?? DateTime.now(),
                                    firstDate:
                                        logFilterDateStart ?? DateTime.now().subtract(const Duration(days: 365 * 10)),
                                    lastDate: DateTime.now(),
                                  )).then((value) {
                            setState(
                              () {
                                logFilterDateEnd = value;
                              },
                            );
                          });
                        },
                        icon: const Icon(Icons.calendar_month, color: Colors.lightBlue)),
                  ],
                ),
                SizedBox(
                    width: double.infinity,
                    child: TextFormField(
                        initialValue: logFilterGearSearch,
                        onChanged: (value) => logFilterGearSearch = value,
                        decoration: InputDecoration(hintText: "Search Gear".tr()))),
              ],
            ),
            actions: [
              ElevatedButton.icon(
                  icon: const Icon(
                    Icons.clear,
                    color: Colors.red,
                  ),
                  onPressed: () {
                    logFilterDateStart = null;
                    logFilterDateEnd = null;
                    List<LogFilter> filters = [];
                    Navigator.pop(context, filters);
                  },
                  label: Text("btn.Clear".tr())),
              ElevatedButton.icon(
                  icon: const Icon(
                    Icons.search,
                    color: Colors.lightBlue,
                  ),
                  onPressed: () {
                    // Build filters
                    List<LogFilter> filters = [];
                    if (logFilterDateStart != null) {
                      filters.add((log) => log.goodFile && log.endTime!.isAfter(logFilterDateStart!));
                    }
                    if (logFilterDateEnd != null) {
                      filters.add((log) =>
                          log.goodFile && log.startTime!.isBefore(logFilterDateEnd!.add(const Duration(days: 1))));
                    }
                    if (logFilterGearSearch?.isNotEmpty ?? false) {
                      filters.add((log) {
                        if (log.gear != null) {
                          final searchStr = log.gear!.toJson().values.join(" ").toLowerCase();
                          final score = logFilterGearSearch!
                              .toLowerCase()
                              .split(RegExp(r"[\s,]"))
                              .where((element) => element.isNotEmpty)
                              .map((each) => tokenSortPartialRatio(each, searchStr) / 100.0)
                              .reduce((a, b) => a * b);
                          return score > 0.98;
                        } else {
                          return false;
                        }
                      });
                    }
                    Navigator.pop(context, filters);
                  },
                  label: Text("Search".tr()))
            ],
          );
        });
      });
}
