import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/util.dart';

enum GpsFixVerdict {
  /// Plausible fix, use normally.
  accept,

  /// Physically impossible relative to the last accepted fix. Drop it.
  reject,

  /// Too many consecutive rejections (or too long since the last good fix).
  /// The previous anchor is probably the bad one, so start fresh from this fix
  /// without deriving speed / vario from the jump.
  reanchor,
}

/// Drops GPS fixes that imply physically impossible motion relative to the last accepted fix.
///
/// Bad GPS can report a far-away position with a nearly identical timestamp, which would
/// otherwise produce an enormous derived speed / vario and poison the smoothed values.
class GpsJumpFilter {
  /// Meters/sec. Well above anything a paramotor / paraglider (or car) will do.
  final double maxHorizontalSpeed;

  /// Meters/sec of GPS altitude change.
  final double maxVerticalSpeed;

  /// After this many consecutive rejections, assume the anchor was the bad fix.
  final int maxConsecutiveRejects;

  /// If the last accepted fix is older than this, re-anchor instead of rejecting.
  final Duration maxAnchorAge;

  int consecutiveRejects = 0;

  GpsJumpFilter({
    this.maxHorizontalSpeed = 100,
    this.maxVerticalSpeed = 40,
    this.maxConsecutiveRejects = 5,
    this.maxAnchorAge = const Duration(seconds: 10),
  });

  GpsFixVerdict check(Geo? last, Position position) {
    if (last == null) {
      consecutiveRejects = 0;
      return GpsFixVerdict.accept;
    }

    final dt = position.timestamp.millisecondsSinceEpoch - last.time;
    if (!_isPlausible(last, position, dt)) {
      consecutiveRejects++;
      if (consecutiveRejects > maxConsecutiveRejects || dt > maxAnchorAge.inMilliseconds) {
        consecutiveRejects = 0;
        return GpsFixVerdict.reanchor;
      }
      return GpsFixVerdict.reject;
    }

    consecutiveRejects = 0;
    return GpsFixVerdict.accept;
  }

  bool _isPlausible(Geo last, Position position, int dtMs) {
    // Duplicate or out-of-order timestamps carry no usable motion information.
    if (dtMs <= 0) return false;

    final dist = latlngCalc.distance(last.latlng, LatLng(position.latitude, position.longitude));
    if (dist / dtMs * 1000 > maxHorizontalSpeed) return false;

    final dAlt = (position.altitude - last.altGps).abs();
    if (dAlt / dtMs * 1000 > maxVerticalSpeed) return false;

    return true;
  }
}
