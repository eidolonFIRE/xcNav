import 'dart:math';

import 'package:flutter/material.dart';
import 'package:xcnav/models/geo.dart';

class WindSolveResult {
  final double airspeed;
  final double windSpd;
  final double windHdg;
  final Offset circleCenter;

  WindSolveResult(this.airspeed, this.windSpd, this.windHdg, this.circleCenter);
}

class Wind with ChangeNotifier {
  /// Most recent wind calculation performed
  DateTime? _lastWindCalc;
  DateTime? get lastWindCalc => _lastWindCalc;

  bool _isRecording = false;

  /// Radians
  double _windHdg = 0;
  double get windHdg => _windHdg;

  /// m/s
  double _windSpd = 0;
  double get windSpd => _windSpd;

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

  void recordReading(double hdg, double spd) {
    _windHdg = hdg;
    _windSpd = spd;

    _lastWindCalc = DateTime.now();
    // notifyListeners();
  }

  WindSolveResult solve(List<double> samplesX, List<double> samplesY) {
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
    final double a1 =
        mZZ * mZ + 4 * covXY * mZ - mXZ * mXZ - mYZ * mYZ - mZ * mZ * mZ;
    final double a0 = mXZ * mXZ * mYY +
        mYZ * mYZ * mXX -
        mZZ * covXY -
        2 * mXZ * mYZ * mXY +
        mZ * mZ * covXY;
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
    final windSpeed = sqrt(pow(xCenter, 2) + pow(yCenter, 2));

    recordReading(atan2(yCenter, xCenter) % (2 * pi), windSpeed);

    return WindSolveResult(radius, windSpd, windHdg, Offset(xCenter, yCenter));
  }
}
