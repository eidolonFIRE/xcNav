import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;

import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

Future<FuelReport?> dialogEditFuelReport(
    {required BuildContext context, required DateTime time, double? amount}) async {
  return showDialog<FuelReport?>(
      context: context,
      builder: (context) {
        final amountFormKey = GlobalKey<FormState>(debugLabel: "FuelReportFormKey");
        final fuelAmountController =
            TextEditingController(text: amount == null ? null : printDoubleSimple(amount, decimals: 2));

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text("Report Fuel Level"),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  intl.DateFormat("h:mm a").format(time),
                  style: const TextStyle(fontSize: 20),
                ),
                SizedBox(
                  width: 80,
                  child: Form(
                    key: amountFormKey,
                    child: TextFormField(
                      controller: fuelAmountController,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                          hintText: getUnitStr(UnitType.fuel, lexical: true),
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
