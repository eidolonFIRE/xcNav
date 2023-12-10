import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:intl/intl.dart' as intl;
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

Future editFuelReports(BuildContext context) {
  final fuelAmountController = TextEditingController();
  final selectedTimeController = TextEditingController();
  final amountFormKey = GlobalKey<FormState>();
  final myTelemetry = Provider.of<MyTelemetry>(context, listen: false);

  return showDialog(
      context: context,
      builder: (context) {
        TimeOfDay? selectedTime;
        DateTime selectedDateTime() => DateTime(clock.now().year, clock.now().month, clock.now().day,
            selectedTime?.hour ?? clock.now().hour, selectedTime?.minute ?? clock.now().minute);

        return AlertDialog(
          title: const Text("Report Fuel in Tank"),
          content: StatefulBuilder(builder: (context, setState) {
            /// Insert a report into the list
            void tryAddNewReport(String text) {
              final value = parseAsDouble(text);

              setState(() {
                myTelemetry.insertFuelReport(selectedDateTime(),
                    (value != null && value.isFinite) ? (value / unitConverters[UnitType.fuel]!(1)) : null);
                fuelAmountController.clear();
                selectedTime = null;
              });
            }

            /// Select a report and update the UI
            void selectReport(FuelReport report) {
              setState(() {
                selectedTime = TimeOfDay(hour: report.time.hour, minute: report.time.minute);
                fuelAmountController.text =
                    printDoubleSimple(unitConverters[UnitType.fuel]!(report.amount), decimals: 2);
              });
            }

            selectedTimeController.text = selectedTime?.format(context) ?? "";

            final List<Widget> listItems = [];

            const unitStyle = TextStyle(fontSize: 10);
            const unitStyleBig = TextStyle(fontSize: 14, color: Colors.grey);

            final overlappingReportIndex = myTelemetry.findFuelReportIndex(selectedDateTime());

            for (int index = 0; index < myTelemetry.fuelReports.length; index++) {
              final e = myTelemetry.fuelReports[index];

              // Insert Report
              listItems.add(GestureDetector(
                onTap: () => selectReport(e),
                child: SizedBox(
                  height: 30,
                  child: Card(
                    color: overlappingReportIndex == index ? Colors.grey.shade600 : Colors.grey.shade700,
                    child: DefaultTextStyle(
                      style: TextStyle(
                          fontWeight: overlappingReportIndex == index ? FontWeight.bold : FontWeight.normal,
                          color: Colors.white),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        Text(intl.DateFormat("h:mm a").format(e.time)),
                        Text.rich(richValue(UnitType.fuel, e.amount,
                            decimals: 2, digits: 3, valueStyle: const TextStyle(fontSize: 16))),
                      ]),
                    ),
                  ),
                ),
              ));
            }

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width - 200,
                    height: max(24, min(MediaQuery.of(context).size.height * 0.6, listItems.length * 30)),
                    child: ListView(
                      // shrinkWrap: true,
                      children: listItems,
                    ),
                  ),

                  if (myTelemetry.sumFuelStat != null) const Divider(),

                  // --- Fuel Stats: summary
                  if (myTelemetry.sumFuelStat != null)
                    DefaultTextStyle(
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                        const Text("Avg"),
                        Text.rich(TextSpan(children: [
                          TextSpan(
                              text: printDoubleSimple(unitConverters[UnitType.fuel]!(myTelemetry.sumFuelStat!.rate),
                                  decimals: 1)),
                          TextSpan(text: fuelRateStr, style: unitStyleBig)
                        ])),
                        Text.rich(TextSpan(children: [
                          TextSpan(
                              text: printDoubleSimple(
                                  unitConverters[UnitType.distCoarse]!(
                                      myTelemetry.sumFuelStat!.mpl / unitConverters[UnitType.fuel]!(1)),
                                  decimals: 1)),
                          TextSpan(text: fuelEffStr, style: unitStyleBig)
                        ]))
                      ]),
                    ),

                  const Divider(),

                  // --- Edit
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    SizedBox(
                      width: 80,
                      child: GestureDetector(
                          onTap: () {
                            showTimePicker(
                                    context: context, initialTime: selectedTime ?? TimeOfDay.fromDateTime(clock.now()))
                                .then((value) {
                              setState(() {
                                selectedTime = value;
                              });
                            });
                          },
                          child: TextFormField(
                            controller: selectedTimeController,
                            enabled: false,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                                hintText: "Now", // intl.DateFormat("h:mm a").format(clock.now()),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                enabled: true,
                                contentPadding: const EdgeInsets.all(4)),
                          )
                          // Text(selectedTime?.format(context) ?? intl.DateFormat("h:mm a").format(clock.now())),
                          ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Form(
                        key: amountFormKey,
                        child: TextFormField(
                          controller: fuelAmountController,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                              hintText: getUnitStr(UnitType.fuel, lexical: true),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.all(4)),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          autofocus: true,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]'))],
                          validator: (value) {
                            if (value != null) {
                              if (value.trim().isEmpty) return "Empty";
                            }
                            return null;
                          },
                          onFieldSubmitted: (value) => tryAddNewReport(fuelAmountController.text),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: myTelemetry.findFuelReportIndex(selectedDateTime()) != null
                          ? const Icon(
                              Icons.edit,
                              color: Colors.white,
                            )
                          : const Icon(
                              Icons.add,
                              color: Colors.lightGreen,
                            ),
                      label: Container(), // const Text("Add"),
                      onPressed: () => tryAddNewReport(fuelAmountController.text),
                    )
                  ]),
                ],
              ),
            );
          }),
        );
      });
}
