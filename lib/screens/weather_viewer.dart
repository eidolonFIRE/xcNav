import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/weather.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/sounding_plot_therm.dart';
import 'package:xcnav/widgets/sounding_plot_wind.dart';

class WeatherViewer extends StatefulWidget {
  const WeatherViewer({Key? key}) : super(key: key);

  @override
  State<WeatherViewer> createState() => _WeatherViewerState();
}

class _WeatherViewerState extends State<WeatherViewer> {
  double? selectedY;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
        length: 2,
        child: Scaffold(
            appBar: AppBar(
              title: const Text("Weather"),
              bottom: const TabBar(tabs: [
                Tab(icon: Icon(Icons.pin_drop)),
                Tab(
                  icon: Icon(Icons.route),
                )
              ]),
            ),
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                /// === View Sounding at current geo
                FutureBuilder<Sounding?>(
                    future: Provider.of<Weather>(context).getSounding(),
                    builder: (context, sounding) {
                      if (sounding.hasData && sounding.data != null) {
                        double myBaro = Provider.of<MyTelemetry>(context,
                                    listen: false)
                                .baro
                                ?.hectpascal ??
                            pressureFromElevation(
                                Provider.of<MyTelemetry>(context, listen: false)
                                    .geo
                                    .alt,
                                1013.25);
                        // Get the sample from selection
                        SoundingSample? sample;
                        if (selectedY != null) {
                          sample = sounding.data!.sampleBaro(
                              pressureFromElevation(
                                  (MediaQuery.of(context).size.width -
                                          selectedY!) /
                                      (MediaQuery.of(context).size.width) *
                                      6000.0,
                                  1013.25));
                        } else {
                          sample = sounding.data!.sampleBaro(myBaro);
                        }

                        return Column(
                          // crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Text(
                                "Current Sounding",
                                style: Theme.of(context).textTheme.headline4,
                              ),
                            ),

                            // Divider(),

                            /// --- Isobar values (values at altitude)
                            Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Flex(
                                  direction: Axis.horizontal,
                                  children: [
                                    Flexible(
                                        fit: FlexFit.tight,
                                        flex: 3,
                                        child: Text.rich(
                                          TextSpan(children: [
                                            richValue(
                                                UnitType.distFine,
                                                getElevation(
                                                    sample.baroAlt, 1013.25)),
                                            const TextSpan(text: ",  "),
                                            TextSpan(
                                                style: const TextStyle(
                                                    color: Colors.blue),
                                                text: sample.dpt == null
                                                    ? "?"
                                                    : "${cToF(sample.dpt)!.toStringAsFixed(0)} F"),
                                            const TextSpan(text: ",  "),
                                            TextSpan(
                                                style: const TextStyle(
                                                    color: Colors.red),
                                                text: sample.tmp == null
                                                    ? "?"
                                                    : "${cToF(sample.tmp)!.toStringAsFixed(0)} F"),
                                          ]),
                                          style: const TextStyle(fontSize: 24),
                                          textAlign: TextAlign.center,
                                        )),
                                    Flexible(
                                        fit: FlexFit.tight,
                                        flex: 1,
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(left: 10),
                                          child: Stack(children: [
                                            if (sample.wHdg != null)
                                              Container(
                                                transformAlignment:
                                                    const Alignment(0, 0),
                                                transform: Matrix4.rotationZ(
                                                    sample.wHdg!),
                                                child: SvgPicture.asset(
                                                  "assets/images/arrow.svg",
                                                  width: 100,
                                                  height: 100,
                                                  // color: Colors.blue,
                                                ),
                                              ),
                                            Align(
                                              alignment: Alignment.center,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 42, bottom: 42),
                                                child: Text(
                                                  (sample.wVel != null)
                                                      ? printDouble(
                                                          value: unitConverters[
                                                                  UnitType
                                                                      .speed]!(
                                                              sample.wVel!),
                                                          digits: 2,
                                                          decimals: 0)
                                                      : "",
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                          ]),
                                        )),
                                  ],
                                )),

                            /// --- Graph plots
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 10, right: 10),
                              child: SizedBox(
                                width: MediaQuery.of(context).size.width,
                                height: MediaQuery.of(context).size.width,
                                child: Listener(
                                    behavior: HitTestBehavior.opaque,
                                    onPointerDown: (e) => setState(() {
                                          selectedY = e.localPosition.dy;
                                        }),
                                    onPointerMove: (e) => setState(() {
                                          selectedY = e.localPosition.dy;
                                        }),
                                    child:
                                        Stack(fit: StackFit.loose, children: [
                                      Flex(
                                        direction: Axis.horizontal,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Flexible(
                                            fit: FlexFit.tight,
                                            flex: 3,
                                            child: ClipRect(
                                              child: CustomPaint(
                                                painter:
                                                    SoundingPlotThermPainter(
                                                        sounding.data!,
                                                        selectedY,
                                                        myBaro),
                                              ),
                                            ),
                                          ),
                                          Flexible(
                                            fit: FlexFit.tight,
                                            flex: 1,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 10),
                                              child: ClipRRect(
                                                child: CustomPaint(
                                                  painter:
                                                      SoundingPlotWindPainter(
                                                          sounding.data!,
                                                          selectedY,
                                                          myBaro),
                                                ),
                                              ),
                                            ),
                                          )
                                        ],
                                      ),
                                      if (selectedY == null)
                                        const Align(
                                          alignment: Alignment.center,
                                          child: Text.rich(
                                            TextSpan(children: [
                                              WidgetSpan(
                                                  child: Icon(
                                                Icons.touch_app,
                                                size: 26,
                                              )),
                                              TextSpan(
                                                  text: "  Select an Altitude")
                                            ]),
                                            style: TextStyle(
                                                fontSize: 18,
                                                shadows: [
                                                  Shadow(
                                                      color: Colors.black,
                                                      blurRadius: 20)
                                                ]),
                                          ),
                                        ),
                                    ])),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Text(
                                "NAM-NEST-conus updated  ${DateTime.now().difference(Provider.of<Weather>(context, listen: false).lastPull ?? DateTime.now()).inMinutes.toString()}  minutes ago.",
                                style: const TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic),
                              ),
                            )
                          ],
                        );
                      } else {
                        return Center(
                            child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(10.0),
                              child: Text("Fetching"),
                            ),
                            CircularProgressIndicator(),
                          ],
                        ));
                      }
                    }),

                /// === Weather through route
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text("Weather along route"),
                      Text("comming soon... "),
                    ],
                  ),
                ),
              ],
            )));
  }
}
