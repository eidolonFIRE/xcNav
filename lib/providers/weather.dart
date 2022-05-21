import 'dart:async';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/models/grib2.dart';
import 'package:xcnav/providers/my_telemetry.dart';

class SoundingSample {
  double? tmp;
  double? dpt;
  double? wVel;
  double? wHdg;
  double? baroAlt;
  double? uGrd;
  double? vGrd;
  SoundingSample({this.baroAlt});
}

typedef Sounding = List<SoundingSample>;

class Weather with ChangeNotifier {
  late final BuildContext context;
  final String dateStr = DateFormat("yyyyMMdd").format(DateTime.now());

  /// Timestamp for last weather request
  DateTime? lastPull;
  Sounding? _sounding;

  Weather(BuildContext ctx) {
    context = ctx;

    // Provider.of<MyTelemetry>(context, listen: false).addListener(() {
    //   // Listen for movement so we can update the weather.

    // });
  }

  Future<Sounding> getSounding() {
    final completer = Completer<Sounding>();
    // TODO: geofence trigger
    if (lastPull == null ||
        lastPull!
            .subtract(const Duration(minutes: 60))
            .isAfter(DateTime.now())) {
      MyTelemetry myTelemetry =
          Provider.of<MyTelemetry>(context, listen: false);
      final box =
          Rect.fromCircle(center: myTelemetry.geo.latLngOffset, radius: 0.5);

      _updateSounding(box).then((value) => completer.complete(value));
    } else {
      completer.complete(_sounding!);
    }
    return completer.future;
  }

  Future<Sounding> _updateSounding(Rect bounds) async {
    // TODO: set url time correctly
    lastPull = DateTime.now();
    debugPrint(bounds.toString());
    String uri =
        "https://nomads.ncep.noaa.gov/cgi-bin/filter_nam.pl?file=nam.t00z.awphys00.tm00.grib2&lev_1000_mb=on&lev_500_mb=on&lev_525_mb=on&lev_550_mb=on&lev_575_mb=on&lev_600_mb=on&lev_625_mb=on&lev_650_mb=on&lev_675_mb=on&lev_700_mb=on&lev_725_mb=on&lev_750_mb=on&lev_775_mb=on&lev_800_mb=on&lev_825_mb=on&lev_850_mb=on&lev_875_mb=on&lev_900_mb=on&lev_925_mb=on&lev_950_mb=on&lev_975_mb=on&var_DPT=on&var_TMP=on&var_UGRD=on&var_VGRD=on&subregion=&leftlon=${bounds.left.toStringAsFixed(2)}&rightlon=${bounds.right.toStringAsFixed(2)}&toplat=${bounds.bottom.toStringAsFixed(2)}&bottomlat=${bounds.top.toStringAsFixed(2)}&dir=%2Fnam.$dateStr";
    // debugPrint(uri);
    final response = await http.get(Uri.parse(uri));

    debugPrint("--- Response: ${response.statusCode} ${response.reasonPhrase}");

    debugPrint("Pulled NAM weather.");
    _sounding = _buildSounding(
        bounds.center.dy, bounds.center.dx, parseRawFile(response.bodyBytes));

    return _sounding!;
  }

  Sounding _buildSounding(double lat, double lng, List<Section> data) {
    Map<double, SoundingSample> sampleStack = {};
    for (var each in data) {
      if (each.baroElev != null) {
        if (sampleStack[each.baroElev!] == null) {
          // Make New Entry
          sampleStack[each.baroElev!] = SoundingSample(baroAlt: each.baroElev!);
        }

        var curSample = sampleStack[each.baroElev!]!;

        // Interpolate Data
        final grid = each.gridConfig!;
        final latSize = grid.dY / 111320.0;
        final lngSize = grid.dX / (40075000 * cos(grid.la1 * pi / 180.0) / 360);
        // print("Aprox. Grid Size: $latSize x $lngSize");
        final yIndex = (lat - grid.la1) / latSize * grid.numY;
        final xIndex = (lng - grid.lo1) / lngSize * grid.numX;
        final vY1 = each.data![yIndex.ceil()][xIndex.floor()];
        final vY2 = each.data![yIndex.floor()][xIndex.floor()];
        final vY3 = each.data![yIndex.ceil()][xIndex.ceil()];
        final vY4 = each.data![yIndex.floor()][xIndex.ceil()];
        final vYF = (yIndex % 1.0) * vY2 + vY1 * (1 - (yIndex % 1.0));
        final vYC = (yIndex % 1.0) * vY4 + vY3 * (1 - (yIndex % 1.0));
        final v = (xIndex % 1.0) * vYC + vYF * (1 - (xIndex % 1.0));

        if (each.product == "TMP") curSample.tmp = v;
        if (each.product == "DPT") curSample.dpt = v;
        if (each.product == "UGRD") curSample.uGrd = v;
        if (each.product == "VGRD") curSample.vGrd = v;
        if ((each.product == "UGRD" || each.product == "VGRD") &&
            curSample.uGrd != null &&
            curSample.vGrd != null) {
          // Both wind vector now set, so we can calculate...
          curSample.wVel =
              sqrt(pow(curSample.uGrd!, 2) + pow(curSample.vGrd!, 2));
          curSample.wHdg = atan2(curSample.uGrd!, curSample.vGrd!);
        }
      }
    }

    debugPrint("Built Sounding.");
    return sampleStack.values.toList();
  }
}
