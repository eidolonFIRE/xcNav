import 'dart:math';

import 'package:flutter/material.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:xcnav/dialogs/fuel_adjustment.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/screens/home.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/wind_plot.dart';

Widget moreInstrumentsDrawer() {
  return Consumer<MyTelemetry>(
    builder: (context, myTelemetry, child) => SafeArea(
      child: Dialog(
          // elevation: 10,
          backgroundColor: Colors.grey.shade900,
          insetPadding: const EdgeInsets.only(left: 0, right: 0, top: 60),
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Flight Timer
              ListTile(
                leading: const Icon(Icons.flight_takeoff),
                title: myTelemetry.takeOff != null
                    ? Builder(builder: (context) {
                        int remMin =
                            ((DateTime.now().millisecondsSinceEpoch - myTelemetry.takeOff!.millisecondsSinceEpoch) /
                                    60000)
                                .ceil();
                        String value = (remMin >= 60) ? (remMin / 60).toStringAsFixed(1) : remMin.toString();
                        String unit = (remMin >= 60) ? " hr" : " min";
                        return Text.rich(TextSpan(children: [
                          const TextSpan(text: "Launched   ", style: TextStyle(color: Colors.grey)),
                          TextSpan(
                              text: DateFormat("h:mm a").format(myTelemetry.takeOff!),
                              style: Theme.of(context).textTheme.headline5),
                          const TextSpan(text: " ,    ", style: TextStyle(color: Colors.grey)),
                          TextSpan(text: value, style: Theme.of(context).textTheme.headline5),
                          TextSpan(text: unit, style: Theme.of(context).textTheme.headline6),
                          const TextSpan(text: "  ago.", style: TextStyle(color: Colors.grey)),
                        ]));
                      })
                    : const Text(
                        "On the ground...",
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
              ),
              // --- Fuel Indicator
              ListTile(
                minVerticalPadding: 0,
                leading: const Icon(Icons.local_gas_station, size: 30),
                title: GestureDetector(
                  onTap: () => {showFuelDialog(context)},
                  child: Card(
                    color: Colors.grey.shade800,
                    child: (myTelemetry.fuel > 0)
                        ? Builder(builder: (context) {
                            int remMin = min(999 * 60, (myTelemetry.fuel / myTelemetry.fuelBurnRate * 60).ceil());
                            String value = (remMin >= 60) ? (remMin / 60).toStringAsFixed(1) : remMin.toString();
                            String unit = (remMin >= 60) ? "hr" : "min";
                            return Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Text.rich(
                                  richValue(UnitType.fuel, myTelemetry.fuel,
                                      decimals: 1,
                                      valueStyle: Theme.of(context).textTheme.headline4,
                                      unitStyle: instrLabel),
                                  softWrap: false,
                                ),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: value, style: Theme.of(context).textTheme.headline4),
                                      TextSpan(text: unit, style: instrLabel)
                                    ],
                                  ),
                                  softWrap: false,
                                ),
                              ],
                            );
                          })
                        : Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Text(
                              "Set Fuel Level",
                              style: Theme.of(context).textTheme.headline5,
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ),
              ),

              const Divider(thickness: 2),

              /// --- Wind Chart
              Consumer<Wind>(
                builder: (context, wind, child) => IntrinsicHeight(
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          mainAxisSize: MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                "Wind Detector",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                            ToggleButtons(
                                selectedColor: Colors.white,
                                selectedBorderColor: Colors.lightBlueAccent,
                                color: Colors.grey.shade700,
                                // fillColor: Colors.blue,
                                constraints:
                                    BoxConstraints(minWidth: MediaQuery.of(context).size.width / 5, minHeight: 40),
                                borderRadius: const BorderRadius.all(Radius.circular(4)),
                                onPressed: (index) {
                                  if (index == 0) {
                                    if (wind.isRecording) wind.stop();
                                  } else {
                                    if (!wind.isRecording) wind.start();
                                  }
                                },
                                isSelected: [!wind.isRecording, wind.isRecording],
                                children: const [Text("Hold"), Text("Measure")]),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                const Text("Airspeed"),
                                wind.result != null
                                    ? Text.rich(richValue(UnitType.speed, wind.result!.airspeed,
                                        digits: 3,
                                        valueStyle: const TextStyle(fontSize: 30),
                                        unitStyle: const TextStyle(fontSize: 14, color: Colors.grey)))
                                    : const Text("?"),
                              ]),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                const Text("Wind Speed"),
                                wind.result != null
                                    ? Text.rich(
                                        richValue(UnitType.speed, wind.result!.windSpd,
                                            digits: 3,
                                            valueStyle: const TextStyle(
                                              fontSize: 30,
                                            ),
                                            unitStyle: const TextStyle(fontSize: 14, color: Colors.grey)),
                                      )
                                    : const Text("?"),
                              ]),
                            )
                          ],
                        ),
                      ),

                      /// --- Wind Readings Polar Chart
                      Card(
                        color: Colors.black26,
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.5,
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                wind.result == null
                                    ? Center(
                                        child: wind.isRecording
                                            ? Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Padding(
                                                    padding: EdgeInsets.all(10.0),
                                                    child:
                                                        Text("Slowly Turn 1/4 Circle", style: TextStyle(fontSize: 18)),
                                                  ),
                                                  CircularProgressIndicator(
                                                    strokeWidth: 3,
                                                  )
                                                ],
                                              )
                                            : const Text("Tap Measure\nto begin",
                                                textAlign: TextAlign.center, style: TextStyle(fontSize: 18)))
                                    : ClipRect(
                                        child: CustomPaint(
                                          painter: WindPlotPainter(
                                              3,
                                              wind.result!.samplesX,
                                              wind.result!.samplesY,
                                              wind.result!.maxSpd * 1.1,
                                              wind.result!.circleCenter,
                                              wind.result!.airspeed,
                                              wind.isRecording),
                                        ),
                                      ),
                                const Align(alignment: Alignment.topCenter, child: Text("N")),
                                const Align(alignment: Alignment.bottomCenter, child: Text("S")),
                                const Align(alignment: Alignment.centerLeft, child: Text("W")),
                                const Align(alignment: Alignment.centerRight, child: Text("E")),
                              ],
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),

              const Divider(thickness: 2),

              // --- Altitude Chart
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: charts.TimeSeriesChart(
                    [
                      charts.Series<Geo, DateTime>(
                        id: "Altitude",
                        data: myTelemetry.recordGeo,
                        colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
                        domainFn: (value, _) => DateTime.fromMillisecondsSinceEpoch(value.time),
                        measureFn: (value, _) => unitConverters[UnitType.distFine]!(value.alt),
                      )
                    ],
                    defaultRenderer: charts.LineRendererConfig(includeArea: true, stacked: true),
                    animate: false,

                    behaviors: [
                      charts.ChartTitle("Altitude   (${getUnitStr(UnitType.distFine)} )",
                          behaviorPosition: charts.BehaviorPosition.start,
                          titleOutsideJustification: charts.OutsideJustification.middleDrawArea,
                          titleStyleSpec: const charts.TextStyleSpec(color: charts.MaterialPalette.white)),
                    ],

                    domainAxis: const charts.DateTimeAxisSpec(
                        renderSpec: charts.SmallTickRendererSpec(

                            // Tick and Label styling here.
                            labelStyle: charts.TextStyleSpec(
                                fontSize: 14, // size in Pts.
                                color: charts.MaterialPalette.white),

                            // Change the line colors to match text color.
                            lineStyle: charts.LineStyleSpec(color: charts.MaterialPalette.white))),

                    /// Assign a custom style for the measure axis.
                    primaryMeasureAxis: const charts.NumericAxisSpec(
                        tickProviderSpec: charts.BasicNumericTickProviderSpec(desiredMinTickCount: 4),
                        renderSpec: charts.GridlineRendererSpec(

                            // Tick and Label styling here.
                            labelStyle: charts.TextStyleSpec(
                                fontSize: 14, // size in Pts.
                                color: charts.MaterialPalette.white),

                            // Change the line colors to match text color.
                            lineStyle: charts.LineStyleSpec(color: charts.MaterialPalette.white))),
                  ),
                ),
              ),
            ],
          )),
    ),
  );
}
