import 'dart:math';

import 'package:flutter/material.dart';
import 'package:xcnav/models/vector.dart';
import 'package:xcnav/util.dart';

/// Result of a wind solution.
///
/// Units
/// - airspeed: meters/second (m/s)
/// - windSpd: meters/second (m/s)
/// - windHdg: radians, normalized to [0, 2π)
/// - circleCenter: cartesian center (m/s) of fitted speed circle
/// - maxSpd: max observed groundspeed scaled by 1.1 (for plotting)
/// - timestamp: wall-clock time when the solve completed
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
  WindSolveResult(
    this.airspeed,
    this.windSpd,
    this.windHdg,
    this.circleCenter,
    this.maxSpd,
    this.samplesX,
    this.samplesY,
    this.timestamp,
  );
}

class Wind with ChangeNotifier {
  Wind({bool isRunningReplayFromLog = false}) : _isRunningReplayFromLog = isRunningReplayFromLog;

  /// Recorded ground vectors: heading (rad) and speed (m/s).
  List<Vector> _samples = [];
  List<Vector> get samples => _samples;

  /// Most recent wind calculation performed
  WindSolveResult? _result;
  WindSolveResult? get result => _result;

  /// True when feeding samples from an offline log replay.
  final bool _isRunningReplayFromLog;

  /// Logging verbosity; higher prints more. Only active during log replay.
  int _printVerbosity = 0;

  /// Configure the logging verbosity for this instance.
  void setPrintVerbosity(int v) => _printVerbosity = v;

  /// Internal logging helper that respects verbosity and replay state.
  void _log(String msg, {int v = 1}) {
    if (_isRunningReplayFromLog && v <= _printVerbosity) {
      debugPrint(msg);
      //print(msg); // This collates with the unit test's prints to screen than debugPrint
    }
  }

  // ================== Tunable thresholds ==================
  /// Minimum samples required to attempt convergence.
  static const int _minSamplesForConvergence = 4;

  /// Required field-of-view (radians) across headings for a valid solve.
  static const double _fovThresholdRad = 80 * (pi / 180); // 80°

  /// Maximum plausible windspeed and airspeed
  static const double _maxPlausibleWindspeedMph = 120;
  static const double _maxPlausibleAirspeedMph = 63;

  /// Convergence residual tolerance as a fraction of radius (airspeed).
  /// All used samples must be within this to be considered converged.
  static const double _convergeResidualRel = 0.70; // ±70%

  /// When converged, new samples must fit within this relative residual to be accepted.
  static const double _convergedAcceptResidualRel = 0.50; // ±50%

  /// Unconverged: drop only obviously bad points with residual beyond this relative amount
  /// (applied after a tentative fit if available).
  static const double _obviousErrantResidualRel = 1.5; // >±150%

  /// Aging windows for keeping samples.
  static const Duration _expireUnconverged = Duration(minutes: 10);
  static const Duration _expireConverged = Duration(minutes: 10);

  /// If converged and no applicable samples for this long, fall back to unconverged
  /// and stop reporting until reconverged.
  static const Duration _staleConvergedTimeout = Duration(minutes: 5);

  /// Always drop the older sample if a new one arrives within this heading span.
  static const double _dedupeAngleRad = 3 * pi / 180; // 3°
  /// Require at least this many newer samples within the span before dropping an older one.
  static const int _dedupeMinNewerCount = 3;

  /// Remaining headway downwind given course-to-wind `theta` and speeds.
  /// Guards sqrt for small negative inputs from FP error.
  static double remainingHeadway(double theta, double mySpd, double wSpd) =>
      sqrt(max(0, pow(mySpd, 2) - pow(wSpd * sin(theta), 2))) - cos(theta) * wSpd;

  /// Clear any computed result and recorded samples.
  void clearResult() {
    _result = null;
    _samples.clear();
    notifyListeners();
  }

  /// Ingest a new ground vector sample and attempt to solve for wind.
  ///
  /// Behavior
  /// - Trims very old samples when timestamps are present (older than [maxSampleAge]).
  /// - Requires >4 samples and field-of-view >90° before solving for stability.
  /// - Notifies listeners when a new result is produced.
  void handleVector(Vector newSample) {

    // When replaying from a log, prefer the sample's timestamp; otherwise use wall clock time.
    final DateTime now = (_isRunningReplayFromLog && newSample.timestamp != null)
        ? newSample.timestamp!
        : DateTime.now();

    // If converged but stale (no accepted samples for a while), reset and start over.
    if (_converged && _lastAccepted != null && now.difference(_lastAccepted!) > _staleConvergedTimeout) {
      _log('Wind: state -> UNCONVERGED (stale > ${_staleConvergedTimeout.inMinutes}m). Dropping samples older than 5m', v: 1);
      _converged = false;
      _result = null; // stop reporting
      _samples.clear();
      notifyListeners();
    }

    // Trim samples by current state aging policy.
    _expireOlderThan(now.subtract(_converged ? _expireConverged : _expireUnconverged));

    // Dedupe by heading: always drop older samples within 3° of the new heading.
    _dropOlderWithinHeading(newSample.hdg, _dedupeAngleRad);

    bool accepted = false;

    if (_converged && _result != null) {
      // Check if new sample fits current circle within ±40%.
      final r = _result!;
      final residual = _residualForSample(newSample, r.circleCenter, r.airspeed);
      final rel = residual / max(1e-6, r.airspeed);
      if (rel <= _convergedAcceptResidualRel) {
        _samples.add(newSample);
        accepted = true;
        _lastAccepted = now;
        _attemptConverge(now); // refine fit while staying converged
      }
      // If not accepted, keep sample out; if we remain stale, state will flip above.
      else {
        final hdgDeg = (newSample.hdg * 180 / pi) % 360;
        _log('Wind: drop sample (converged non-compliance) residualRel=${rel.toStringAsFixed(2)} hdg=${hdgDeg.toStringAsFixed(1)}° spd=${newSample.value.toStringAsFixed(2)}m/s', v: 2);
      }
    } else {
      // Unconverged: only reject obviously errant samples, otherwise accept.
      if (_isSaneSample(newSample)) {
        _samples.add(newSample);
        accepted = true;
        _lastAccepted = now;
        _attemptConverge(now);
      } else {
        final hdgDeg = (newSample.hdg * 180 / pi) % 360;
        _log('Wind: drop sample (invalid) hdg=${hdgDeg.toStringAsFixed(1)}° spd=${newSample.value.toStringAsFixed(2)}m/s', v: 2);
      }
    }

    // If we didn't accept and are unconverged, ensure no result is reported.
    if (!_converged) {
      _result = null;
      if (accepted) notifyListeners();
    }
  }

  // ================== State & helpers ==================
  bool _converged = false;
  DateTime? _lastAccepted;

  /// Remove samples with timestamps older than the cutoff.
  void _expireOlderThan(DateTime cutoff) {
    if (_samples.isEmpty) return;
    final before = _samples.length;
    _samples.removeWhere((s) => s.timestamp != null && s.timestamp!.isBefore(cutoff));
    final expired = before - _samples.length;
    if (expired > 0) {
      _log('Wind: expired $expired old sample(s); remaining ${_samples.length}', v: 3);
    }
  }

  /// Drop older samples near the given heading if sufficiently represented by newer ones.
  void _dropOlderWithinHeading(double hdg, double angleRad) {
    if (_samples.isEmpty) return;

    // Collect candidate indices near the heading
    final candidates = <int>[];
    for (int ii = 0; ii < _samples.length; ii++) {
      final each = _samples[ii];
      if (deltaHdg(each.hdg, hdg).abs() <= angleRad) {
        candidates.add(ii);
      }
    }
    if (candidates.isEmpty) return;

    // For each candidate, count newer ones in the same span; drop if enough newer exist
    final toRemove = <int>[];
    for (final ii in candidates) {
      int newer = 0;
      for (final jj in candidates) {
        if (jj > ii) newer++;
      }
      if (newer >= _dedupeMinNewerCount) {
        toRemove.add(ii);
      }
    }

    if (toRemove.isEmpty) return;
    toRemove.sort((a, b) => b.compareTo(a));
    for (final idx in toRemove) {
      _samples.removeAt(idx);
    }
    final hdgDeg = (hdg * 180 / pi) % 360;
    _log('Wind: removed ${toRemove.length} near-duplicate older sample(s) within '
        '${(angleRad * 180 / pi).toStringAsFixed(1)}° of hdg=${hdgDeg.toStringAsFixed(1)}° '
        '(minNewer=$_dedupeMinNewerCount)', v: 3);
  }

  bool _isSaneSample(Vector v) {
    return v.value.isFinite && v.value > 0 && v.value < 90 && v.hdg.isFinite;
  }

  /// Try to converge given current samples/time. Sets _converged/_result as appropriate.
  void _attemptConverge(DateTime now) {
    final wasConverged = _converged;

    if (_samples.length < _minSamplesForConvergence) return;

    final fov = _computeFov(_samples);
    if (fov < _fovThresholdRad) {
        if (wasConverged) {
            _log('Wind: state -> UNCOVERGED due to field of view ${fov.toStringAsFixed(2)} < ${_fovThresholdRad.toStringAsFixed(2)}', v: 1);
        } else {
            _log('Wind: Not converging due to field of view ${fov.toStringAsFixed(2)} < ${_fovThresholdRad.toStringAsFixed(2)}', v: 3);
        }
        _result = null;
        _converged = false;
        return;
    }

    final res = _solve(_samples, now, applyGates: true);
    if (res == null) {
        // Either the wind speed or the air speed have gotten implausible.  Just reset and start over.
        if (wasConverged) {
            _log('Wind: state -> UNCOVERGED due to _solve plausibility checks', v: 1);
        }
        _result = null;
        _converged = false;
        _samples.clear();
        return;
    }

    final residuals = _computeResiduals(_samples, res.circleCenter, res.airspeed);
    final maxRel = residuals
        .map((e) => e / max(1e-6, res.airspeed))
        .fold<double>(0, (prev, cur) => cur > prev ? cur : prev);

    if (maxRel <= _convergeResidualRel) {
      _result = res;
      _converged = true;
      _lastAccepted ??= now;
      notifyListeners();
      if (!wasConverged) {
        final hdgDeg = (res.windHdg * 180 / pi) % 360;
        _log('Wind: state -> CONVERGED with ${_samples.length} samples | '
            'air=${res.airspeed.toStringAsFixed(2)}m/s wind=${res.windSpd.toStringAsFixed(2)}m/s '
            'hdg=${hdgDeg.toStringAsFixed(1)}°', v: 1);
      }
    } else {
      _log('Wind: Not converging due to residual error ${maxRel.toStringAsFixed(2)} > ${_convergeResidualRel.toStringAsFixed(2)}', v: 3);

      // Not converged: only drop obviously errant points.
      final toKeep = <Vector>[];
      for (int ii = 0; ii < _samples.length; ii++) {
        final rel = residuals[ii] / max(1e-6, res.airspeed);
        if (rel <= _obviousErrantResidualRel) toKeep.add(_samples[ii]);
      }
      if (toKeep.isNotEmpty && toKeep.length != _samples.length) {
        final dropped = _samples.length - toKeep.length;
        _samples = toKeep;
        _log('Wind: removed $dropped obvious outlier sample(s) while unconverged', v: 2);
      }
    }
  }

  /// Compute the minimal circular arc (field-of-view) that contains all headings.
  ///
  /// Robust to wrap-around across 0°/360°. Order-independent.
  /// Returns radians in [0, 2π]. A value ≥ π/2 means at least 90° of spread.
  double _computeFov(List<Vector> samples) {
    if (samples.isEmpty) return 0;
    if (samples.length == 1) return 0;

    // Normalize headings to [0, 2π) and sort
    final angles = samples
        .map((v) => ((v.hdg % (2 * pi)) + 2 * pi) % (2 * pi))
        .toList()
      ..sort();

    // Find the largest gap between consecutive angles (including wrap gap)
    // Then, the fov is 2pi minus the gap

    // Start with the wraparound gap of the smallest and largest angles
    double maxGap = (angles.first + 2 * pi) - angles.last;
    for (int ii = 1; ii < angles.length; ii++) {
      final gap = angles[ii] - angles[ii - 1];
      if (gap > maxGap) {
          maxGap = gap;
      }
    }
    // The minimal arc length covering all angles is 2π - largest gap.
    return (2 * pi) - maxGap;
  }

  /// Compute residual distances from each sample point to the fitted circle.
  List<double> _computeResiduals(List<Vector> vectors, Offset center, double radius) {
    final cx = center.dx;
    final cy = center.dy;
    final out = <double>[];
    for (final v in vectors) {
      final x = cos(v.hdg - pi / 2) * v.value;
      final y = sin(v.hdg - pi / 2) * v.value;
      final dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2));
      out.add((dist - radius).abs());
    }
    return out;
  }

  /// Compute residual for a single sample to the fitted circle.
  double _residualForSample(Vector v, Offset center, double radius) {
    final cx = center.dx;
    final cy = center.dy;
    final x = cos(v.hdg - pi / 2) * v.value;
    final y = sin(v.hdg - pi / 2) * v.value;
    final dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2));
    return (dist - radius).abs();
  }

  /// Solve wind vector and airspeed from ground speed/heading samples.
  ///    returns a solution or null. When [applyGates] is true,
  ///
  /// Method
  /// - Project polar measurements (hdg, speed) into cartesian (x,y) in m/s.
  /// - Remove DC offset, then fit a circle via Newton–Taubin.
  /// - Circle center => wind vector; radius => airspeed.
  /// - Applies plausibility gates (wind speed and radius constraints).
  ///
  /// Reference: https://people.cas.uab.edu/~mosya/cl/
  ///
  WindSolveResult? _solve(List<Vector> samples, DateTime now, {required bool applyGates}) {
    // debugPrint("Solve Wind");
    double mXX = 0;
    double mYY = 0;
    double mXY = 0;
    double mXZ = 0;
    double mYZ = 0;
    double mZZ = 0;

    // Transform to cartesian. Note the -π/2 rotation aligns 0 rad to +Y.
    final samplesX = samples.map((e) => cos(e.hdg - pi / 2) * e.value).toList();
    final samplesY = samples.map((e) => sin(e.hdg - pi / 2) * e.value).toList();
    final maxSpd = samples.reduce((a, b) => a.value > b.value ? a : b).value * 1.1;

    // Remove DC offset (translate to center over origin).
    final xMean = samplesX.reduce((a, b) => a + b) / samplesX.length;
    final yMean = samplesY.reduce((a, b) => a + b) / samplesY.length;
    for (int ii = 0; ii < samplesX.length; ii++) {
      final xI = samplesX[ii] - xMean;
      final yI = samplesY[ii] - yMean;
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
      if (!dY.isFinite || dY == 0) {
        xnew = 0;
        break;
      }
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

    // Compute final offset and radius of the fitted circle.
    final det = xnew * xnew - xnew * mZ + covXY;
    if (!det.isFinite || det.abs() < 1e-12) {
      return null;
    }
    double xCenter = (mXZ * (mYY - xnew) - mYZ * mXY) / det / 2;
    double yCenter = (mYZ * (mXX - xnew) - mXZ * mXY) / det / 2;
    final radius = sqrt(max(0, pow(xCenter, 2) + pow(yCenter, 2) + mZ));
    xCenter += xMean;
    yCenter += yMean;
    final windSpd = sqrt(max(0, pow(xCenter, 2) + pow(yCenter, 2)));
    // Align heading to [0, 2π). atan2 uses x/y per our coordinate transform.
    final windHdg = (atan2(xCenter, -yCenter) + 2 * pi) % (2 * pi);

    // Confidence gates: limit implausible wind and radius.

    final maxPlausibleWindspeedMps = _maxPlausibleWindspeedMph / 2.23694;
    final maxPlausibleAirspeedMps = _maxPlausibleAirspeedMph / 2.23694;

    if (applyGates) {
      if (!(windSpd < maxPlausibleWindspeedMps && radius < maxPlausibleAirspeedMps)) return null;
    }

    return WindSolveResult(
      radius,
      windSpd,
      windHdg,
      Offset(xCenter, yCenter),
      maxSpd,
      samplesX,
      samplesY,
      now,
    );
  }
}
