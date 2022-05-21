import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/providers/weather.dart';
import 'package:xcnav/widgets/sounding_plot.dart';

class WeatherViewer extends StatefulWidget {
  const WeatherViewer({Key? key}) : super(key: key);

  @override
  State<WeatherViewer> createState() => _WeatherViewerState();
}

class _WeatherViewerState extends State<WeatherViewer> {
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
              children: [
                /// --- View Sounding at current geo
                Column(
                  // crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Text(
                        "Sounding Here",
                        style: Theme.of(context).textTheme.headline6,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.width,
                        child: FutureBuilder<Sounding>(
                          future: Provider.of<Weather>(context, listen: false)
                              .getSounding(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return CustomPaint(
                                  painter: SoundingPlotPainter(snapshot.data!));
                            } else {
                              return CircularProgressIndicator();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                /// Weather through route
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
