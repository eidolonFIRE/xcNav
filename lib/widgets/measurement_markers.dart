import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/views/map/map_symbols.dart';

/// Ground elevation and distance so far, at each measurement point
SymbolLayer measurementSymbols(List<LatLng> points) {
  const valueStyle = TextStyle(fontSize: 20);
  final unitStyle = TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic, fontSize: 12);

  List<MapSymbol> symbols = [];

  LatLng? prev;
  double sumDist = 0;
  for (int index = 0; index < points.length; index++) {
    final e = points[index];
    sumDist += latlngCalc.distance(e, prev ?? e);
    final elevation = sampleDem(e, false);
    final elevationSpan = elevation != null
        ? richValue(UnitType.distFine, elevation, digits: 5, valueStyle: valueStyle, unitStyle: unitStyle)
        : null;
    final distSpan = (index > 0 || points.length > 1)
        ? richValue(UnitType.distCoarse, sumDist, valueStyle: valueStyle, unitStyle: unitStyle, autoDecimalThresh: 10.0)
        : null;
    symbols.add(MapSymbol(
        id: "$index",
        point: e,
        width: 75,
        height: 54,
        alignment: Alignment.topRight,
        imageKey: "measurement_${elevationSpan?.toPlainText()}_${distSpan?.toPlainText()}",
        child: Card(
          color: Colors.black.withAlpha(100),
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // --- Elevation
              Text.rich(
                elevationSpan ??
                    const WidgetSpan(
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
              ),
              // --- Cumulative Distance
              if (distSpan != null)
                Text.rich(
                  distSpan,
                  softWrap: false,
                )
            ]),
          ),
        )));
    prev = e;
  }

  return SymbolLayer("measurementLabels", symbols: symbols);
}
