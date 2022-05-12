import 'package:flutter/material.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:xcnav/dialogs/fuel_adjustment.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/screens/home.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/icon_image.dart';
import 'package:xcnav/widgets/wind_plot.dart';

Widget moreInstrumentsDrawer() {
  return Consumer<MyTelemetry>(
    builder: (context, myTelemetry, child) => SafeArea(
      child: Dialog(
          // elevation: 10,
          backgroundColor: Colors.grey[900],
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
                        int remMin = ((DateTime.now().millisecondsSinceEpoch -
                                    myTelemetry
                                        .takeOff!.millisecondsSinceEpoch) /
                                60000)
                            .ceil();
                        String value = (remMin >= 60)
                            ? (remMin / 60).toStringAsFixed(1)
                            : remMin.toString();
                        String unit = (remMin >= 60) ? " hr" : " min";
                        return Text.rich(TextSpan(children: [
                          const TextSpan(
                              text: "Launched   ",
                              style: TextStyle(color: Colors.grey)),
                          TextSpan(
                              text: DateFormat("h:mm a")
                                  .format(myTelemetry.takeOff!),
                              style: Theme.of(context).textTheme.headline5),
                          const TextSpan(
                              text: " ,    ",
                              style: TextStyle(color: Colors.grey)),
                          TextSpan(
                              text: value,
                              style: Theme.of(context).textTheme.headline5),
                          TextSpan(
                              text: unit,
                              style: Theme.of(context).textTheme.headline6),
                          const TextSpan(
                              text: "  ago.",
                              style: TextStyle(color: Colors.grey)),
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
                    color: Colors.grey[800],
                    child: (myTelemetry.fuel > 0)
                        ? Builder(builder: (context) {
                            int remMin = (myTelemetry.fuel /
                                    myTelemetry.fuelBurnRate *
                                    60)
                                .ceil();
                            String value = (remMin >= 60)
                                ? (remMin / 60).toStringAsFixed(1)
                                : remMin.toString();
                            String unit = (remMin >= 60) ? "hr" : "min";
                            return Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                          text: convertFuelValue(
                                                  Provider.of<Settings>(context)
                                                      .displayUnitsFuel,
                                                  myTelemetry.fuel)
                                              .toStringAsFixed(1),
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline4),
                                      TextSpan(
                                          text: unitStrFuel[
                                              Provider.of<Settings>(context)
                                                  .displayUnitsFuel],
                                          style: instrLabel)
                                    ],
                                  ),
                                  softWrap: false,
                                ),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                          text: value,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline4),
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
                builder: (context, wind, child) => Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        mainAxisSize: MainAxisSize.max,
                        // crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Wind Detector",
                            style: TextStyle(color: Colors.grey),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 20, right: 20),
                            child: Divider(),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 6, right: 6),
                            child: ListTile(
                              title: const Text("Airspeed"),
                              trailing: wind.result != null
                                  ? Text.rich(TextSpan(children: [
                                      TextSpan(
                                          style: const TextStyle(fontSize: 30),
                                          text: convertSpeedValue(
                                                  Provider.of<Settings>(context,
                                                          listen: false)
                                                      .displayUnitsSpeed,
                                                  wind.result!.airspeed)
                                              .toStringAsFixed(0)),
                                      TextSpan(
                                          style: const TextStyle(
                                              fontSize: 14, color: Colors.grey),
                                          text: unitStrSpeed[
                                              Provider.of<Settings>(context,
                                                      listen: false)
                                                  .displayUnitsSpeed]!)
                                    ]))
                                  : const Text("?"),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 6, right: 6),
                            child: ListTile(
                              title: const Text("Wind Speed"),
                              trailing: wind.result != null
                                  ? Text.rich(TextSpan(children: [
                                      TextSpan(
                                          style: const TextStyle(
                                            fontSize: 30,
                                          ),
                                          text: convertSpeedValue(
                                                  Provider.of<Settings>(context,
                                                          listen: false)
                                                      .displayUnitsSpeed,
                                                  wind.result!.windSpd)
                                              .toStringAsFixed(0)),
                                      TextSpan(
                                          style: const TextStyle(
                                              fontSize: 14, color: Colors.grey),
                                          text: unitStrSpeed[
                                              Provider.of<Settings>(context,
                                                      listen: false)
                                                  .displayUnitsSpeed]!)
                                    ]))
                                  : const Text("?"),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Hold",
                                  style: TextStyle(
                                    color: wind.isRecording
                                        ? Colors.grey[700]
                                        : Colors.white,
                                  )),
                              Switch(
                                  value: wind.isRecording,
                                  inactiveThumbImage: IconImageProvider(
                                      Icons.pause,
                                      color: Colors.black),
                                  activeThumbImage: IconImageProvider(
                                      Icons.play_arrow,
                                      color: Colors.black),
                                  onChanged: (value) {
                                    if (value) {
                                      wind.windSampleFirst =
                                          myTelemetry.recordGeo.length - 1;
                                      wind.windSampleLast = null;
                                    } else {
                                      wind.windSampleLast =
                                          myTelemetry.recordGeo.length - 1;
                                    }
                                    wind.isRecording = value;
                                  }),
                              Text("Active",
                                  style: TextStyle(
                                    color: wind.isRecording
                                        ? Colors.white
                                        : Colors.grey[700],
                                  )),
                            ],
                          ),
                        ],
                      ),
                    ),

                    /// --- Wind Readings Polar Chart
                    Card(
                      color: Colors.black26,
                      child: Container(
                        // width: MediaQuery.of(context).size.width * 2 / 3,
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 2 / 3,
                            maxHeight: 200),

                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              wind.result == null
                                  ? Center(
                                      child: wind.isRecording
                                          ? const Text("Measuring...")
                                          : const Text("No Measurements"))
                                  : ClipRect(
                                      child: CustomPaint(
                                        painter: WindPlotPainter(
                                            3,
                                            wind.result!.samplesX,
                                            wind.result!.samplesY,
                                            wind.result!.maxSpd,
                                            wind.result!.circleCenter,
                                            wind.result!.airspeed),
                                      ),
                                    ),
                              const Align(
                                  alignment: Alignment.topCenter,
                                  child: Text("N")),
                              const Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Text("S")),
                              const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text("W")),
                              const Align(
                                  alignment: Alignment.centerRight,
                                  child: Text("E")),
                            ],
                          ),
                        ),
                      ),
                    )
                  ],
                ),
              ),

              const Divider(thickness: 2),

              // --- Altitude Chart
              Card(
                color: Colors.black26,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: charts.TimeSeriesChart(
                    [
                      charts.Series<Geo, DateTime>(
                        id: "Altitude",
                        data: myTelemetry.recordGeo,
                        colorFn: (_, __) =>
                            charts.MaterialPalette.blue.shadeDefault,
                        domainFn: (value, _) =>
                            DateTime.fromMillisecondsSinceEpoch(value.time),
                        measureFn: (value, _) => convertDistValueFine(
                            Provider.of<Settings>(context, listen: false)
                                .displayUnitsDist,
                            value.alt),
                      )
                    ],
                    defaultRenderer: charts.LineRendererConfig(
                        includeArea: true, stacked: true),
                    animate: false,

                    behaviors: [
                      charts.ChartTitle(
                          "Altitude   (${unitStrDistFine[Provider.of<Settings>(context).displayUnitsDist]} )",
                          behaviorPosition: charts.BehaviorPosition.start,
                          titleOutsideJustification:
                              charts.OutsideJustification.middleDrawArea,
                          titleStyleSpec: const charts.TextStyleSpec(
                              color: charts.MaterialPalette.white)),
                    ],

                    domainAxis: const charts.DateTimeAxisSpec(
                        renderSpec: charts.SmallTickRendererSpec(

                            // Tick and Label styling here.
                            labelStyle: charts.TextStyleSpec(
                                fontSize: 14, // size in Pts.
                                color: charts.MaterialPalette.white),

                            // Change the line colors to match text color.
                            lineStyle: charts.LineStyleSpec(
                                color: charts.MaterialPalette.white))),

                    /// Assign a custom style for the measure axis.
                    primaryMeasureAxis: const charts.NumericAxisSpec(
                        tickProviderSpec: charts.BasicNumericTickProviderSpec(
                            desiredMinTickCount: 4),
                        renderSpec: charts.GridlineRendererSpec(

                            // Tick and Label styling here.
                            labelStyle: charts.TextStyleSpec(
                                fontSize: 14, // size in Pts.
                                color: charts.MaterialPalette.white),

                            // Change the line colors to match text color.
                            lineStyle: charts.LineStyleSpec(
                                color: charts.MaterialPalette.white))),
                  ),
                ),
              ),
            ],
          )),
    ),
  );
}
