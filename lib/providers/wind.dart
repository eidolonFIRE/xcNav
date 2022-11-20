import 'dart:math';

import 'package:flutter/material.dart';
import 'package:xcnav/models/geo.dart';

class WindSolveResult {
  late final double airspeed;
  late final double windSpd;

  /// Radians
  final double windHdg;
  final Offset circleCenter;
  final double maxSpd;
  late final DateTime timestamp;
  List<double> samplesX;
  List<double> samplesY;
  WindSolveResult(this.airspeed, this.windSpd, this.windHdg, this.circleCenter, this.maxSpd, this.samplesX,
      this.samplesY, this.timestamp);
}

class Wind with ChangeNotifier {
  /// Recorded
  List<Vector> samples = [];

  /// Most recent wind calculation performed
  WindSolveResult? _result;
  WindSolveResult? get result => _result;

  static const maxSampleAge = Duration(minutes: 5);

  static double remainingHeadway(double theta, double mySpd, double wSpd) =>
      sqrt(pow(mySpd, 2) - pow(wSpd * sin(theta), 2)) - cos(theta) * wSpd;

  void clearResult() {
    _result = null;
    samples.clear();
    notifyListeners();
  }

  void handleVector(Vector newSample) {
    samples.add(newSample);
    while (samples.isNotEmpty &&
        (samples.first.timestamp == null || samples.first.timestamp!.isBefore(DateTime.now().subtract(maxSampleAge)))) {
      // Remove 10 at a time for performance
      samples.removeRange(0, min(10, samples.length));
    }

    if (samples.length > 4) {
      // Check sampled field-of-view is sufficient for confidence
      var prev = samples.first.hdg;
      var left = prev;
      var right = prev;
      for (var each in samples) {
        final cur = prev + deltaHdg(each.hdg, prev);

        left = min(left, cur);
        right = max(right, cur);
        prev = cur;
      }
      final fov = right - left;
      // debugPrint("FOV: $fov  (${samples.length} samples)");

      if ((samples.length >= 14 && fov > pi / 4) || fov > pi / 2) solve(samples);
    }
  }

  /// #Solve wind direction from GPS samples.
  /// https://people.cas.uab.edu/~mosya/cl/
  void solve(List<Vector> samples) {
    // debugPrint("Solve Wind");
    double mXX = 0;
    double mYY = 0;
    double mXY = 0;
    double mXZ = 0;
    double mYZ = 0;
    double mZZ = 0;

    // Transform to cartesian
    final samplesX = samples.map((e) => cos(e.hdg - pi / 2) * e.value).toList();
    final samplesY = samples.map((e) => sin(e.hdg - pi / 2) * e.value).toList();
    final maxSpd = samples.reduce((a, b) => a.value > b.value ? a : b).value * 1.1;

    // Remove DC offset (translate to cener over origin)
    final xMean = samplesX.reduce((a, b) => a + b) / samplesX.length;
    final yMean = samplesY.reduce((a, b) => a + b) / samplesY.length;
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
      // debugPrint("ynew: $ynew, xnew: $xnew");
      if ((ynew).abs() > (yold).abs()) {
        // debugPrint("Newton-Taubin goes wrong direction: |ynew| > |yold|");
        xnew = 0;
        break;
      }
      double dY = a1 + xnew * (a22 + xnew * a33);
      double xold = xnew;
      xnew = xold - ynew / dY;
      if (((xnew - xold) / xnew).abs() < epsilon) break;
      if (iter >= iterMax) {
        // debugPrint("Newton-Taubin will not converge");
        xnew = 0;
      }
      if (xnew < 0) {
        // debugPrint("Newton-Taubin negative root:  x=$xnew");
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
    final windHdg = atan2(xCenter, -yCenter) % (2 * pi);

    // More conditions for good result
    if (windSpd < 90 && radius < 40) {
      _result = WindSolveResult(
          radius, windSpd, windHdg, Offset(xCenter, yCenter), maxSpd, samplesX, samplesY, DateTime.now());
      notifyListeners();
    }
  }
}
