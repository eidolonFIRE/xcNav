import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import 'package:xcnav/providers/my_telemetry.dart';

// --- Fuel Level Editor Dialog
void showFuelDialog(BuildContext context) {
  showDialog(
      context: context,
      builder: (context) {
        TextStyle numbers = const TextStyle(fontSize: 40);

        return Consumer<MyTelemetry>(builder: (context, myTelemetry, child) {
          return AlertDialog(
            title: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                Text("Fuel Level"),
                Text("Burn Rate"),
              ],
            ),
            content: Row(
              children: [
                // --- Fuel Level
                Card(
                  color: Colors.grey.shade700,
                  child: Row(children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            onPressed: () => {myTelemetry.updateFuel(1)},
                            icon: const Icon(
                              Icons.keyboard_arrow_up,
                              color: Colors.lightGreen,
                            )),
                        Text(
                          myTelemetry.fuel.floor().toString(),
                          style: numbers,
                          textAlign: TextAlign.center,
                        ),
                        IconButton(
                            onPressed: () => {myTelemetry.updateFuel(-1)},
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.red,
                            )),
                      ],
                    ),
                    Text(
                      ".",
                      style: numbers,
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          onPressed: () => {myTelemetry.updateFuel(0.1)},
                          icon: const Icon(
                            Icons.keyboard_arrow_up,
                            color: Colors.lightGreen,
                          )),
                      Text(
                        ((myTelemetry.fuel % 1) * 10).round().toString(),
                        style: numbers,
                        textAlign: TextAlign.center,
                      ),
                      IconButton(
                          onPressed: () => {myTelemetry.updateFuel(-0.1)},
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.red,
                          )),
                    ])
                  ]),
                ),

                // --- Burn Rate
                Card(
                  color: Colors.grey.shade700,
                  child: Row(children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            onPressed: () =>
                                {myTelemetry.updateFuelBurnRate(1)},
                            icon: const Icon(
                              Icons.keyboard_arrow_up,
                              color: Colors.lightGreen,
                            )),
                        Text(
                          myTelemetry.fuelBurnRate.floor().toString(),
                          style: numbers,
                          textAlign: TextAlign.center,
                        ),
                        IconButton(
                            onPressed: () =>
                                {myTelemetry.updateFuelBurnRate(-1)},
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.red,
                            )),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(1, 6, 1, 0),
                      child: Text(
                        ".",
                        style: numbers,
                      ),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          onPressed: () =>
                              {myTelemetry.updateFuelBurnRate(0.1)},
                          icon: const Icon(
                            Icons.keyboard_arrow_up,
                            color: Colors.lightGreen,
                          )),
                      Text(
                        ((myTelemetry.fuelBurnRate % 1) * 10)
                            .round()
                            .toString(),
                        style: numbers,
                        textAlign: TextAlign.center,
                      ),
                      IconButton(
                          onPressed: () =>
                              {myTelemetry.updateFuelBurnRate(-0.1)},
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.red,
                          )),
                    ])
                  ]),
                )
              ],
            ),
            // actions: [
            //   ElevatedButton.icon(
            //       label: const Text("Update"),
            //       onPressed: () {
            //         Navigator.pop(context);
            //       },
            //       icon: const Icon(
            //         Icons.check,
            //         size: 20,
            //         color: Colors.lightGreen,
            //       )),
            //   ElevatedButton.icon(
            //       label: const Text("Cancel"),
            //       onPressed: () => {Navigator.pop(context)},
            //       icon: const Icon(
            //         Icons.cancel,
            //         size: 20,
            //         color: Colors.red,
            //       )),
            // ],
          );
        });
      });
}
