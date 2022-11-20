import 'dart:async';
import 'dart:math';

import 'package:bisection/bisect.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/models/grib2.dart';
import 'package:xcnav/providers/my_telemetry.dart';

// Gas constant for dry air at the surface of the Earth
const rd = 287;
// Specific heat at constant pressure for dry air
const cpd = 1005;
// Molecular weight ratio
const epsilon = 18.01528 / 28.9644;
// Heat of vaporization of water
const lv = 2501000;
// Ratio of the specific gas constant of dry air to the specific gas constant for water vapour
const satPressure0c = 6.112;
// C + celsiusToK -> K
const celsiusToK = 273.15;
const L = -6.5e-3;
const g = 9.80665;

/// Computes the temperature at the given pressure assuming dry processes.
/// t0 is the starting temperature at p0 (degree Celsius).
double dryLapse(double p, double t0, double p0) {
  return (t0 + celsiusToK) * pow(p / p0, rd / cpd) - celsiusToK;
}

double pressureFromElevation(double e, double refp) {
  e = e * 3.28084;
  return pow((-(e / 145366.45 - 1)), 1 / 0.190284).toDouble() * refp;
}

double getElevation(double p, double p0) {
  const t0 = 288.15;
  //const p0 = 1013.25;
  return (t0 / L) * (pow(p / p0, (-L * rd) / g) - 1);
}

/// Computes the mixing ration of a gas.
double mixingRatio(double partialPressure, double totalPressure) {
  return (epsilon * partialPressure) / (totalPressure - partialPressure);
}

/// Computes the saturation mixing ratio of water vapor.
double saturationMixingRatio(double p, double tK) {
  return mixingRatio(saturationVaporPressure(tK), p);
}

/// Computes the saturation water vapor (partial) pressure
double saturationVaporPressure(double tK) {
  final tC = tK - celsiusToK;
  return satPressure0c * exp((17.67 * tC) / (tC + 243.5));
}

/// Computes the temperature gradient assuming liquid saturation process.
double moistGradientT(double p, double tK) {
  final rs = saturationMixingRatio(p, tK);
  final n = rd * tK + lv * rs;
  final d = cpd + (pow(lv, 2) * rs * epsilon) / (rd * pow(tK, 2));
  return (1 / p) * (n / d);
}

double? cToF(double? c) {
  return c != null ? (c * 9 / 5 + 32) : null;
}

class SoundingSample {
  /// Celcius
  double? tmp;

  /// Celcius
  double? _dpt;
  double? rh;
  double? wVel;
  double? wHdg;
  double baroAlt;
  double? uGrd;
  double? vGrd;
  SoundingSample({required this.baroAlt});

  double? get dpt => _dpt ?? (rh != null ? (tmp! - (100 - rh!) / 5.0) : null);

  SoundingSample blend(SoundingSample other, double ratio) {
    var sample = SoundingSample(baroAlt: baroAlt * (1 - ratio) + other.baroAlt * ratio);
    // tmp
    if (tmp != null && other.tmp != null) {
      sample.tmp = tmp! * (1 - ratio) + other.tmp! * ratio;
    } else {
      sample.tmp = tmp ?? other.tmp;
    }
    // rh
    if (rh != null && other.rh != null) {
      sample.rh = rh! * (1 - ratio) + other.rh! * ratio;
    } else {
      sample.rh = rh ?? other.rh;
    }
    // vGrd
    if (vGrd != null && other.vGrd != null) {
      sample.vGrd = vGrd! * (1 - ratio) + other.vGrd! * ratio;
    } else {
      sample.vGrd = vGrd ?? other.vGrd;
    }
    // uGrd
    if (uGrd != null && other.uGrd != null) {
      sample.uGrd = uGrd! * (1 - ratio) + other.uGrd! * ratio;
    } else {
      sample.uGrd = uGrd ?? other.uGrd;
    }
    sample.wVel = sqrt(pow(sample.uGrd!, 2) + pow(sample.vGrd!, 2));
    sample.wHdg = atan2(sample.uGrd!, sample.vGrd!);
    return sample;
  }
}

class Sounding {
  final List<SoundingSample> data;
  final LatLng center;

  Sounding(this.data, this.center);

  SoundingSample sampleBaro(double baroAlt) {
    // debugPrint("Searching for baro: $baroAlt");
    if (baroAlt < data.first.baroAlt) return data.first;

    final index = bisect<double>(data.map((e) => e.baroAlt).toList(), baroAlt, compare: (a, b) => (a - b).toInt()) - 1;

    return data[index]
        .blend(data[index + 1], (baroAlt - data[index].baroAlt) / (data[index + 1].baroAlt - data[index].baroAlt));
  }
}

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

  Future<Sounding?> getSounding() {
    final completer = Completer<Sounding?>();
    MyTelemetry myTelemetry = Provider.of<MyTelemetry>(context, listen: false);
    if (lastPull == null ||
        DateTime.now().subtract(const Duration(minutes: 60)).isAfter(lastPull!) ||
        (_sounding != null &&
            ((_sounding!.center.longitude - myTelemetry.geo.lng).abs() > 0.2 ||
                (_sounding!.center.latitude - myTelemetry.geo.lat).abs() > 0.2))) {
      final box = Rect.fromCircle(center: myTelemetry.geo.latlngOffset, radius: 0.3);

      _updateSounding(box).then((value) => completer.complete(value));
    } else {
      completer.complete(_sounding);
    }
    return completer.future;
  }

  Future<Sounding?> _updateSounding(Rect bounds) async {
    lastPull = DateTime.now();
    debugPrint(bounds.toString());

    /// Buffer time for then to post the file.
    const expectedPostDelay = Duration(hours: 4);
    // Subtract some buffer time
    var genTime = DateTime.now().toUtc().subtract(expectedPostDelay);
    // Round back to last 6hr posting
    genTime = genTime.subtract(Duration(hours: genTime.hour % 6));
    // forecast ahead number of hours
    final aheadTime = (DateTime.now().toUtc().difference(genTime).inHours).floor().toString().padLeft(2, "0");
    String uri =
        "https://nomads.ncep.noaa.gov/cgi-bin/filter_nam_conusnest.pl?file=nam.t${genTime.hour.toString().padLeft(2, "0")}z.conusnest.hiresf$aheadTime.tm00.grib2&lev_10_m_above_ground=on&lev_2_m_above_ground=on&lev_1000_mb=on&lev_500_mb=on&lev_525_mb=on&lev_550_mb=on&lev_575_mb=on&lev_600_mb=on&lev_625_mb=on&lev_650_mb=on&lev_675_mb=on&lev_700_mb=on&lev_725_mb=on&lev_750_mb=on&lev_775_mb=on&lev_800_mb=on&lev_825_mb=on&lev_850_mb=on&lev_875_mb=on&lev_900_mb=on&lev_925_mb=on&lev_950_mb=on&lev_975_mb=on&var_RH=on&var_TMP=on&var_UGRD=on&var_VGRD=on&subregion=&leftlon=${bounds.left.toStringAsFixed(2)}&rightlon=${bounds.right.toStringAsFixed(2)}&toplat=${bounds.bottom.toStringAsFixed(2)}&bottomlat=${bounds.top.toStringAsFixed(2)}&dir=%2Fnam.$dateStr";
    debugPrint(uri);
    final response = await http.get(Uri.parse(uri));

    debugPrint("--- Response: ${response.statusCode} ${response.reasonPhrase}");

    debugPrint("Pulled NAM weather.");
    if (response.statusCode == 200) {
      _sounding = _buildSounding(LatLng(bounds.center.dy, bounds.center.dx), parseRawFile(response.bodyBytes));
    } else {
      // Unblock to try again.
      lastPull = null;
    }
    return _sounding;
  }

  Sounding _buildSounding(LatLng center, List<Section> data) {
    Map<double, SoundingSample> sampleStack = {};
    for (var each in data) {
      if (each.baroElev != null) {
        if (sampleStack[each.baroElev!] == null) {
          // Make New Entry
          sampleStack[each.baroElev!] = SoundingSample(baroAlt: each.baroElev!);
        }

        var curSample = sampleStack[each.baroElev!]!;

        // TODO: this lat/lng sampling is naive and needs replaced with correct tangent-cone

        // Interpolate between points
        final grid = each.gridConfig!;
        final latSize = grid.numY * grid.dY / 111320.0;
        final lngSize = grid.numX * grid.dX / (40075017 * cos(center.latitude * pi / 180.0) / 360);
        // print("Aprox. Grid Size: $latSize x $lngSize");
        final yIndex = (center.latitude - grid.la1) / latSize * grid.numY;
        final xIndex = (center.longitude - grid.lo1) / lngSize * grid.numX;
        final vY1 = each.data![yIndex.ceil()][xIndex.floor()];
        final vY2 = each.data![yIndex.floor()][xIndex.floor()];
        final vY3 = each.data![yIndex.ceil()][xIndex.ceil()];
        final vY4 = each.data![yIndex.floor()][xIndex.ceil()];
        final vYF = (yIndex % 1.0) * vY2 + vY1 * (1 - (yIndex % 1.0));
        final vYC = (yIndex % 1.0) * vY4 + vY3 * (1 - (yIndex % 1.0));
        final v = (xIndex % 1.0) * vYC + vYF * (1 - (xIndex % 1.0));

        if (each.product == "TMP") curSample.tmp = v;
        if (each.product == "RH") curSample.rh = v;
        if (each.product == "UGRD") curSample.uGrd = v;
        if (each.product == "VGRD") curSample.vGrd = v;

        if ((each.product == "UGRD" || each.product == "VGRD") && curSample.uGrd != null && curSample.vGrd != null) {
          // Both wind vector now set, so we can calculate...
          curSample.wVel = sqrt(pow(curSample.uGrd!, 2) + pow(curSample.vGrd!, 2));
          curSample.wHdg = atan2(curSample.uGrd!, curSample.vGrd!);
        }
      }
    }

    debugPrint("Built Sounding.");
    return Sounding(sampleStack.values.toList(), center);
  }
}
