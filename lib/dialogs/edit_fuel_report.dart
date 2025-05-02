import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/time_picker.dart';

Future<FuelReport?> dialogEditFuelReport(
    {required BuildContext context, required DateTime time, required DateTimeRange validRange, double? amount}) async {
  return showDialog<FuelReport?>(
      context: context,
      builder: (context) {
        final amountFormKey = GlobalKey<FormState>(debugLabel: "FuelReportFormKey");
        final fuelAmountController =
            TextEditingController(text: amount == null ? null : printDoubleSimple(amount, decimals: 2));

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text("Report Fuel Level"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WheelPickerTime(
                  textStyle: const TextStyle(fontSize: 26.0, height: 1.2),
                  initialTime: time,
                  validRange: validRange,
                  onTimeChanged: (newTime) {
                    setState(() {
                      // Clamp time to valid range if provided
                      if (newTime.isBefore(validRange.start)) {
                        time = validRange.start;
                      } else if (newTime.isAfter(validRange.end)) {
                        time = validRange.end;
                      } else {
                        time = newTime;
                      }
                    });
                  },
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Form(
                        key: amountFormKey,
                        child: TextFormField(
                          controller: fuelAmountController,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24),
                          decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.all(4)),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                          autofocus: true,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]'))],
                          validator: (value) {
                            if (value != null) {
                              if (value.trim().isEmpty) return "Empty";
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Text(
                        getUnitStr(UnitType.fuel),
                        style: const TextStyle(fontSize: 24),
                      ),
                    )
                  ],
                )
              ],
            ),
            actions: [
              if (amount != null)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, FuelReport(DateTime.fromMillisecondsSinceEpoch(0), 0));
                  },
                  icon: const Icon(
                    Icons.delete,
                    color: Colors.red,
                  ),
                  label: const Text("Delete"),
                ),
              ElevatedButton.icon(
                  onPressed: () {
                    if (amountFormKey.currentState?.validate() ?? false) {
                      Navigator.pop(context, FuelReport(time, parseAsDouble(fuelAmountController.text) ?? 0));
                    }
                  },
                  icon: const Icon(
                    Icons.check,
                    color: Colors.lightGreen,
                  ),
                  label: const Text("Save"))
            ],
          );
        });
      });
}
