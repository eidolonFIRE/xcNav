import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' as intl;
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/units.dart';

Future editFuelReports(BuildContext context) {
  final myTelemetry = Provider.of<MyTelemetry>(context, listen: false);
  final fuelAmountLaunch = TextEditingController();
  final fuelAmountNow = TextEditingController();

  const avgStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
  final unitStyleBig = TextStyle(fontSize: 14, color: Colors.grey.shade400);

  return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Report Fuel in Tank"),
          content: StatefulBuilder(builder: (context, setState) {
            String fuelHintLaunch = "  ";
            if (myTelemetry.takeOff != null && myTelemetry.findFuelReportIndex(myTelemetry.takeOff!) == 0) {
              // In flight and has report near take-off time
              fuelHintLaunch =
                  printValue(UnitType.fuel, myTelemetry.fuelReports.first.amount, decimals: 2) ?? fuelHintLaunch;
            } else if (!myTelemetry.inFlight && myTelemetry.fuelReports.isNotEmpty) {
              // Not yet in flight,
              fuelHintLaunch = printValue(UnitType.fuel, myTelemetry.fuelReports.last.amount) ?? fuelHintLaunch;
            }

            String fuelHintNow = "  ";
            final reportNow = myTelemetry.findFuelReportIndex(clock.now());
            final showNow =
                myTelemetry.inFlight && myTelemetry.takeOff!.isBefore(clock.now().subtract(const Duration(minutes: 5)));
            if (reportNow != null && showNow) {
              // Still have recent enough report to just update it
              fuelHintNow =
                  printValue(UnitType.fuel, myTelemetry.fuelReports[reportNow].amount, decimals: 2) ?? fuelHintNow;
            }

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // launch
                  ListTile(
                    leading: const Icon(Icons.flight_takeoff),
                    title: const Text("Launch"),
                    subtitle: myTelemetry.takeOff != null
                        ? Text(intl.DateFormat("h:mm a").format(myTelemetry.takeOff!))
                        : null,
                    trailing: SizedBox(
                      width: 60,
                      child: TextFormField(
                        controller: fuelAmountLaunch,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                            hintText: "$fuelHintLaunch ${getUnitStr(UnitType.fuel, lexical: false)}",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.all(4)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        autofocus: !showNow,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]'))],
                        onFieldSubmitted: (value) {
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ),

                  if (myTelemetry.sumFuelStat != null) const Divider(),

                  // --- Fuel Stats: summary
                  if (myTelemetry.sumFuelStat != null)
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      const Text("Avg"),
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: printValue(UnitType.fuel, myTelemetry.sumFuelStat!.rate, decimals: 1),
                            style: avgStyle),
                        TextSpan(text: fuelRateStr, style: unitStyleBig)
                      ])),
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: printValue(
                                UnitType.distCoarse, myTelemetry.sumFuelStat!.mpl / unitConverters[UnitType.fuel]!(1),
                                decimals: 1),
                            style: avgStyle),
                        TextSpan(text: fuelEffStr, style: unitStyleBig)
                      ]))
                    ]),

                  if (showNow) const Divider(),

                  // now
                  if (showNow)
                    ListTile(
                      leading: reportNow != null
                          ? const Icon(
                              Icons.edit,
                              color: Colors.lightBlue,
                            )
                          : const Icon(
                              Icons.add,
                              color: Colors.lightGreen,
                            ),
                      title: const Text("Now"),
                      trailing: SizedBox(
                        width: 60,
                        child: TextFormField(
                          controller: fuelAmountNow,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                              hintText: "$fuelHintNow ${getUnitStr(UnitType.fuel, lexical: false)}",
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.all(4)),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textInputAction: TextInputAction.done,
                          autofocus: true,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]'))],
                          onFieldSubmitted: (value) {
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        );
      }).then((value) {
    // Update fuel reports
    final parsedLaunch = parseDoubleValue(UnitType.fuel, fuelAmountLaunch.text);
    if (parsedLaunch != null) {
      if (myTelemetry.inFlight && myTelemetry.takeOff != null) {
        debugPrint("Updating launch fuel: $parsedLaunch");
        myTelemetry.insertFuelReport(myTelemetry.takeOff!, parsedLaunch);
      } else {
        debugPrint("Pre-setting fuel level: $parsedLaunch");
        myTelemetry.insertFuelReport(clock.now(), parsedLaunch);
      }
    }

    final parsedNow = parseDoubleValue(UnitType.fuel, fuelAmountNow.text);
    if (parsedNow != null) {
      debugPrint("Updating fuel: $parsedNow");
      myTelemetry.insertFuelReport(clock.now(), parsedNow);
    }
  });
}
