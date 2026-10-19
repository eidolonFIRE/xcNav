import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/util.dart';

enum GpsFixVerdict {
  /// Plausible fix, use normally.
  accept,

  /// Physically impossible relative to the last accepted fix. Drop it.
  reject,

  /// The previous anchor is probably the bad one (the GPS solution shifted and stayed shifted, too many consecutive
  /// rejections, or too long since the last good fix). Start fresh from this fix without deriving speed / vario from
  /// the jump.
  reanchor,
}

/// Drops GPS fixes that imply physically impossible motion relative to the last accepted fix.
///
/// Bad GPS can report a far-away position with a nearly identical timestamp, which would
/// otherwise produce an enormous derived speed / vario and poison the smoothed values.
///
/// Ground speed can't change faster than [maxSpeedChange], whatever the heading does. (Tight turns swing the heading
/// quickly but keep the speed.)
///
/// When the GPS solution shifts (the position jumps tens of meters and then carries on from there), the fix after the
/// jump continues plausibly from the rejected one, and the filter re-anchors on the new track right away.
class GpsJumpFilter {
  /// Meters/sec. Well above anything a paramotor / paraglider (or car) will do.
  final double maxHorizontalSpeed;

  /// Meters/sec of GPS altitude change.
  final double maxVerticalSpeed;

  /// Meters/sec^2 of ground speed change, ignoring direction.
  final double maxSpeedChange;

  /// After this many consecutive rejections, assume the anchor was the bad fix.
  final int maxConsecutiveRejects;

  /// If the last accepted fix is older than this, re-anchor instead of rejecting.
  final Duration maxAnchorAge;

  int consecutiveRejects = 0;

  /// Most recently rejected fix. If the next fix continues from it, the GPS solution shifted.
  Position? _rejected;

  GpsJumpFilter({
    this.maxHorizontalSpeed = 100,
    this.maxVerticalSpeed = 40,
    this.maxSpeedChange = 1.5 * 9.81,
    this.maxConsecutiveRejects = 5,
    this.maxAnchorAge = const Duration(seconds: 10),
  });

  GpsFixVerdict check(Geo? last, Position position) {
    if (last == null) {
      _reset();
      return GpsFixVerdict.accept;
    }

    final dt = position.timestamp.millisecondsSinceEpoch - last.time;

    final rejected = _rejected;
    if (rejected != null &&
        _isPlausible(LatLng(rejected.latitude, rejected.longitude), rejected.altitude,
            rejected.timestamp.millisecondsSinceEpoch, last.spd, position)) {
      // This fix carries on from the rejected one. The GPS solution shifted.
      _reset();
      return GpsFixVerdict.reanchor;
    }

    // The anchor's speed is too old to compare against after a long gap.
    final fromSpd = dt <= maxAnchorAge.inMilliseconds ? last.spd : null;
    if (!_isPlausible(last.latlng, last.altGps, last.time, fromSpd, position)) {
      consecutiveRejects++;
      if (consecutiveRejects > maxConsecutiveRejects || dt > maxAnchorAge.inMilliseconds) {
        _reset();
        return GpsFixVerdict.reanchor;
      }
      // Duplicate or out-of-order fixes can't start a new track.
      _rejected = dt > 0 ? position : null;
      return GpsFixVerdict.reject;
    }

    _reset();
    return GpsFixVerdict.accept;
  }

  void _reset() {
    consecutiveRejects = 0;
    _rejected = null;
  }

  /// [fromSpd] is the ground speed at [from], if known.
  bool _isPlausible(LatLng from, double fromAlt, int fromTime, double? fromSpd, Position position) {
    final dtMs = position.timestamp.millisecondsSinceEpoch - fromTime;
    // Duplicate or out-of-order timestamps carry no usable motion information.
    if (dtMs <= 0) return false;

    final dist = latlngCalc.distance(from, LatLng(position.latitude, position.longitude));
    final spd = dist / dtMs * 1000;
    if (spd > maxHorizontalSpeed) return false;

    if (fromSpd != null && fromSpd.isFinite && (spd - fromSpd).abs() / dtMs * 1000 > maxSpeedChange) return false;

    final dAlt = (position.altitude - fromAlt).abs();
    if (dAlt / dtMs * 1000 > maxVerticalSpeed) return false;

    return true;
  }
}
