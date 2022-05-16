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
          return Dismissible(
            key: const Key("fuelEditorDialog"),
            direction: DismissDirection.vertical,
            onDismissed: (event) =>
                Navigator.popUntil(context, ModalRoute.withName("/home")),
            child: AlertDialog(
              actions: [
                IconButton(
                  onPressed: () =>
                      Navigator.popUntil(context, ModalRoute.withName("/home")),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.red,
                    size: 30,
                  ),
                )
              ],
              title: Flex(
                direction: Axis.horizontal,
                mainAxisSize: MainAxisSize.max,
                children: const [
                  Expanded(
                    child: Text(
                      "Fuel\n(L)",
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      "Burn Rate\n(L/hr)",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              content: Row(
                children: [
                  // --- Fuel Level
                  Card(
                    color: Theme.of(context).backgroundColor,
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
                            ((myTelemetry.fuel * 10).round() / 10)
                                .floor()
                                .toString(),
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
                          ((myTelemetry.fuel * 10).round() % 10).toString(),
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
                    color: Theme.of(context).backgroundColor,
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
                            ((myTelemetry.fuelBurnRate * 10).round() / 10)
                                .floor()
                                .toString(),
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
                          ((myTelemetry.fuelBurnRate * 10).round() % 10)
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
            ),
          );
        });
      });
}
