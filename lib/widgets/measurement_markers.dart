import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/units.dart';

List<Marker> buildMeasurementMarkers(List<LatLng> points) {
  const valueStyle = TextStyle(fontSize: 20);
  final unitStyle = TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic, fontSize: 12);

  List<Marker> retList = [];

  LatLng? prev;
  List<double> sumDist = [];
  for (int index = 0; index < points.length; index++) {
    final e = points[index];
    final dist = latlngCalc.distance(e, prev ?? e);
    retList.add(Marker(
        point: e,
        width: 75,
        height: 54,
        rotate: true,
        anchorPos: AnchorPos.exactly(Anchor(80, 0)),
        builder: ((context) => Card(
              color: Colors.black.withAlpha(100),
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  // --- Elevation
                  FutureBuilder<double?>(
                      future: sampleDem(e, false),
                      builder: (context, snapshot) => Text.rich(
                            snapshot.data != null
                                ? richValue(UnitType.distFine, snapshot.data!,
                                    digits: 5, valueStyle: valueStyle, unitStyle: unitStyle)
                                : const WidgetSpan(
                                    child: Padding(
                                    padding: EdgeInsets.all(4.0),
                                    child: SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                        )),
                                  )),
                            softWrap: false,
                          )),
                  // --- Cumulative Distance
                  if (index > 0 || points.length > 1)
                    Text.rich(
                      TextSpan(children: [
                        richValue(UnitType.distCoarse, sumDist[index],
                            valueStyle: valueStyle, unitStyle: unitStyle, autoDecimalThresh: 10.0),
                        // TextSpan(text: " + "),
                        // richValue(UnitType.distCoarse, dist, valueStyle: valueStyle, unitStyle: unitStyle),
                        // TextSpan(text: ")"),
                      ]),
                      softWrap: false,
                    )
                ]),
              ),
            ))));
    prev = e;
    sumDist.add((sumDist.isEmpty ? 0 : sumDist.last) + dist);
  }

  return retList;
}
