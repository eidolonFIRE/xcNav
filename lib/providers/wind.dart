import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/my_telemetry.dart';

class WindSolveResult {
  late final double airspeed;
  late final double windSpd;

  /// Radians
  final double windHdg;
  final Offset circleCenter;
  final double maxSpd;
  late final int timestamp;
  List<double> samplesX;
  List<double> samplesY;
  WindSolveResult(
      this.airspeed, this.windSpd, this.windHdg, this.circleCenter, this.maxSpd, this.samplesX, this.samplesY) {
    timestamp = DateTime.now().millisecondsSinceEpoch;
  }
}

class Wind with ChangeNotifier {
  /// Most recent wind calculation performed
  WindSolveResult? _result;
  WindSolveResult? get result => _result;

  bool _isRecording = false;

  // Recorded
  int? windSampleFirst;
  int? windSampleLast;

  /// At 5s/sample, this is 20minutes
  static const maxSamples = 240;

  bool get isRecording => _isRecording;
  set isRecording(bool value) {
    _isRecording = value;
    notifyListeners();
  }

  Wind(BuildContext context) {
    Provider.of<MyTelemetry>(context, listen: false).addListener(() {
      final myTelemetry = Provider.of<MyTelemetry>(context, listen: false);
      final cardinality = myTelemetry.recordGeo.length;
      // Conditions for skipping the solve
      if (cardinality < 2 || windSampleFirst == null || ((windSampleFirst ?? cardinality) > cardinality - 3)) return;

      final firstIndex = min(
          cardinality - 1,
          max(
              0,
              max(((isRecording || windSampleLast == null) ? cardinality - 1 : windSampleLast!) - maxSamples,
                  windSampleFirst!)));

      // clamp
      if (windSampleLast != null) {
        windSampleLast = min(cardinality - 1, windSampleLast!);
      }

      final List<Geo> samples = myTelemetry.recordGeo.sublist(firstIndex, windSampleLast);
      if (samples.isNotEmpty) {
        final samplesX = samples.map((e) => cos(e.hdg - pi / 2) * e.spd).toList();
        final samplesY = samples.map((e) => sin(e.hdg - pi / 2) * e.spd).toList();

        final maxSpd = samples.reduce((a, b) => a.spd > b.spd ? a : b).spd * 1.1;

        solve(samplesX, samplesY, maxSpd);
      }
    });
  }

  /// #Solve wind direction from GPS samples.
  /// https://people.cas.uab.edu/~mosya/cl/
  void solve(List<double> samplesX, List<double> samplesY, double maxSpd) {
    // massage the samples into cartesian
    final xMean = samplesX.reduce((a, b) => a + b) / samplesX.length;
    final yMean = samplesY.reduce((a, b) => a + b) / samplesY.length;

    // run the algorithm
    double mXX = 0;
    double mYY = 0;
    double mXY = 0;
    double mXZ = 0;
    double mYZ = 0;
    double mZZ = 0;

    for (int i = 0; i < samplesX.length; i++) {
      final xI = samplesX[i] - xMean;
      final yI = samplesY[i] - yMean;
      final zI = xI * xI + yI * yI;
      mXY += xI * yI;
      mXX += xI * xI;
      mYY += yI * yI;
      mXZ += xI * zI;
      mYZ += yI * zI;
      mZZ += zI * zI;
    }

    mXX /= samplesX.length;
    mYY /= samplesX.length;
    mXY /= samplesX.length;
    mXZ /= samplesX.length;
    mYZ /= samplesX.length;
    mZZ /= samplesX.length;

    final double mZ = mXX + mYY;
    final double covXY = mXX * mYY - mXY * mXY;
    final double a3 = 4 * mZ;
    final double a2 = -3 * mZ * mZ - mZZ;
    final double a1 = mZZ * mZ + 4 * covXY * mZ - mXZ * mXZ - mYZ * mYZ - mZ * mZ * mZ;
    final double a0 = mXZ * mXZ * mYY + mYZ * mYZ * mXX - mZZ * covXY - 2 * mXZ * mYZ * mXY + mZ * mZ * covXY;
    final double a22 = a2 + a2;
    final double a33 = a3 + a3 + a3;

    double xnew = 0;
    double ynew = 1e+20;
    const epsilon = 1e-6;
    const iterMax = 20;

    for (int iter = 1; iter < iterMax; iter++) {
      double yold = ynew;
      ynew = a0 + xnew * (a1 + xnew * (a2 + xnew * a3));
      if ((ynew).abs() > (yold).abs()) {
        debugPrint("Newton-Taubin goes wrong direction: |ynew| > |yold|");
        xnew = 0;
        break;
      }
      double dY = a1 + xnew * (a22 + xnew * a33);
      double xold = xnew;
      xnew = xold - ynew / dY;
      if (((xnew - xold) / xnew).abs() < epsilon) break;
      if (iter >= iterMax) {
        debugPrint("Newton-Taubin will not converge");
        xnew = 0;
      }
      if (xnew < 0) {
        debugPrint("Newton-Taubin negative root:  x=$xnew");
        xnew = 0;
      }
    }

    // compute final offset and radius
    final det = xnew * xnew - xnew * mZ + covXY;
    double xCenter = (mXZ * (mYY - xnew) - mYZ * mXY) / det / 2;
    double yCenter = (mYZ * (mXX - xnew) - mXZ * mXY) / det / 2;
    final radius = sqrt(pow(xCenter, 2) + pow(yCenter, 2) + mZ);
    xCenter += xMean;
    yCenter += yMean;
    final windSpd = sqrt(pow(xCenter, 2) + pow(yCenter, 2));
    final windHdg = atan2(xCenter, yCenter) % (2 * pi);

    _result = WindSolveResult(radius, windSpd, windHdg, Offset(xCenter, yCenter), maxSpd, samplesX, samplesY);
    notifyListeners();
  }
}
