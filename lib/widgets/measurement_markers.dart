import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

List<Marker> buildMeasurementMarkers(List<LatLng> points) {
  const valueStyle = TextStyle(fontSize: 20);
  final unitStyle = TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic, fontSize: 12);

  List<Marker> retList = [];

  LatLng? prev;
  List<double> sumDist = [];
  for (int index = 0; index < points.length; index++) {
    final e = points[index];
    final dist = latlngCalc.distance(e, prev ?? e);
    sumDist.add((sumDist.lastOrNull ?? 0) + dist);
    retList.add(Marker(
        point: e,
        width: 75,
        height: 54,
        rotate: true,
        alignment: Alignment.topRight,
        child: Card(
          color: Colors.black.withAlpha(100),
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // --- Elevation
              Builder(builder: (context) {
                final value = sampleDem(e, false);
                return Text.rich(
                  value != null
                      ? richValue(UnitType.distFine, value, digits: 5, valueStyle: valueStyle, unitStyle: unitStyle)
                      : const WidgetSpan(
                          child: Padding(
                          padding: EdgeInsets.all(4.0),
                          child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 3,
                              )),
                        )),
                  softWrap: false,
                );
              }),
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
        )));
    prev = e;
  }

  return retList;
}
