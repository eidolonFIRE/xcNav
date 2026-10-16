import 'dart:convert';

import 'package:geolocator/geolocator.dart';

const _knotsToMps = 0.514444;

/// Rough user equivalent range error (meters) used to turn HDOP into an accuracy estimate.
const _uere = 5.0;

/// Validate the `*hh` checksum, if present. Returns the sentence body (no `$`, no checksum) or null.
String? nmeaBody(String line) {
  final start = line.lastIndexOf("\$");
  if (start < 0) return null;
  line = line.substring(start + 1).trim();

  final star = line.lastIndexOf("*");
  if (star < 0) return line;

  final body = line.substring(0, star);
  final expected = int.tryParse(line.substring(star + 1), radix: 16);
  if (expected == null) return null;
  int sum = 0;
  for (final c in body.codeUnits) {
    sum ^= c;
  }
  return sum == expected ? body : null;
}

/// Reassemble newline terminated sentences from a fragmented byte stream (eg. BLE notifications).
class NmeaLineSplitter {
  final StringBuffer _buffer = StringBuffer();

  /// Drop partial lines that grow past this (garbage / lost terminator)
  static const maxLength = 256;

  List<String> add(List<int> bytes) {
    _buffer.write(ascii.decode(bytes, allowInvalid: true));
    final parts = _buffer.toString().split("\n");
    _buffer.clear();
    final tail = parts.removeLast();
    if (tail.length < maxLength) _buffer.write(tail);
    return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  void clear() => _buffer.clear();
}

/// `$LK8EX1,pressure,altitude,vario,temperature,battery,*checksum`
class Lk8ex1 {
  /// hPa
  final double? pressure;

  /// Meters (only meaningful if pressure is missing)
  final double? altitude;

  /// m/s
  final double? vario;

  /// Celsius
  final double? temperature;

  /// 0-100
  final double? batteryPercent;
  final double? batteryVolts;

  Lk8ex1({this.pressure, this.altitude, this.vario, this.temperature, this.batteryPercent, this.batteryVolts});

  static Lk8ex1? parse(String body) {
    final f = body.split(",");
    if (f.length < 6 || f[0] != "LK8EX1") return null;

    double? field(int index, double missing) {
      final value = double.tryParse(f[index]);
      return (value == null || value == missing) ? null : value;
    }

    final pressurePa = field(1, 999999);
    final vario = field(3, 9999);
    final battery = field(5, 999);
    return Lk8ex1(
      pressure: pressurePa == null ? null : pressurePa / 100,
      altitude: field(2, 99999),
      vario: vario == null ? null : vario / 100,
      temperature: field(4, 99),
      // Values over 1000 are a percentage offset by 1000, otherwise voltage.
      batteryPercent: battery != null && battery >= 1000 ? battery - 1000 : null,
      batteryVolts: battery != null && battery < 1000 ? battery : null,
    );
  }
}

/// Milliseconds since midnight UTC from `hhmmss.sss`
int? _parseTimeOfDay(String value) {
  if (value.length < 6) return null;
  final h = int.tryParse(value.substring(0, 2));
  final m = int.tryParse(value.substring(2, 4));
  final s = double.tryParse(value.substring(4));
  if (h == null || m == null || s == null) return null;
  return ((h * 60 + m) * 60 * 1000 + s * 1000).round();
}

/// `ddmm.mmmm` / `dddmm.mmmm` with hemisphere
double? _parseCoord(String value, String hemi) {
  final dot = value.indexOf(".");
  final degDigits = (dot < 0 ? value.length : dot) - 2;
  if (degDigits < 1) return null;
  final deg = int.tryParse(value.substring(0, degDigits));
  final min = double.tryParse(value.substring(degDigits));
  if (deg == null || min == null) return null;
  final coord = deg + min / 60;
  return (hemi == "S" || hemi == "W") ? -coord : coord;
}

/// `$--GGA` fix data
class NmeaGga {
  /// Milliseconds since midnight UTC
  final int timeOfDay;
  final double lat;
  final double lng;

  /// 0 = no fix
  final int fixQuality;
  final int? satellites;
  final double? hdop;

  /// Meters MSL
  final double? altitude;

  NmeaGga(
      {required this.timeOfDay,
      required this.lat,
      required this.lng,
      required this.fixQuality,
      this.satellites,
      this.hdop,
      this.altitude});

  static NmeaGga? parse(String body) {
    final f = body.split(",");
    if (f.length < 10 || f[0].length != 5 || !f[0].endsWith("GGA")) return null;
    final time = _parseTimeOfDay(f[1]);
    final lat = _parseCoord(f[2], f[3]);
    final lng = _parseCoord(f[4], f[5]);
    final quality = int.tryParse(f[6]);
    if (time == null || lat == null || lng == null || quality == null) return null;
    return NmeaGga(
        timeOfDay: time,
        lat: lat,
        lng: lng,
        fixQuality: quality,
        satellites: int.tryParse(f[7]),
        hdop: double.tryParse(f[8]),
        altitude: double.tryParse(f[9]));
  }
}

/// `$--RMC` recommended minimum data
class NmeaRmc {
  /// UTC
  final DateTime time;
  final bool valid;
  final double lat;
  final double lng;

  /// m/s
  final double? speed;

  /// Degrees true
  final double? course;

  NmeaRmc({required this.time, required this.valid, required this.lat, required this.lng, this.speed, this.course});

  int get timeOfDay => time.difference(DateTime.utc(time.year, time.month, time.day)).inMilliseconds;

  static NmeaRmc? parse(String body) {
    final f = body.split(",");
    if (f.length < 10 || f[0].length != 5 || !f[0].endsWith("RMC")) return null;
    final timeOfDay = _parseTimeOfDay(f[1]);
    final lat = _parseCoord(f[3], f[4]);
    final lng = _parseCoord(f[5], f[6]);
    final date = f[9];
    if (timeOfDay == null || lat == null || lng == null || date.length != 6) return null;
    final day = int.tryParse(date.substring(0, 2));
    final month = int.tryParse(date.substring(2, 4));
    final year = int.tryParse(date.substring(4, 6));
    if (day == null || month == null || year == null) return null;
    final knots = double.tryParse(f[7]);
    return NmeaRmc(
        time: DateTime.utc(2000 + year, month, day).add(Duration(milliseconds: timeOfDay)),
        valid: f[2] == "A",
        lat: lat,
        lng: lng,
        speed: knots == null ? null : knots * _knotsToMps,
        course: double.tryParse(f[8]));
  }
}

/// Pairs GGA (altitude, quality) and RMC (date, speed, course) sentences from the same epoch into a [Position].
class NmeaFixAssembler {
  NmeaGga? _gga;
  NmeaRmc? _rmc;

  /// Returns a position once both sentences for an epoch have arrived and the fix is valid.
  Position? addGga(NmeaGga gga) {
    _gga = gga;
    return _tryAssemble();
  }

  Position? addRmc(NmeaRmc rmc) {
    _rmc = rmc;
    return _tryAssemble();
  }

  Position? _tryAssemble() {
    final gga = _gga;
    final rmc = _rmc;
    if (gga == null || rmc == null || gga.timeOfDay != rmc.timeOfDay) return null;
    _gga = null;
    _rmc = null;
    if (!rmc.valid || gga.fixQuality == 0 || gga.altitude == null) return null;

    return Position(
      latitude: gga.lat,
      longitude: gga.lng,
      timestamp: rmc.time.toLocal(),
      accuracy: (gga.hdop ?? 10) * _uere,
      altitude: gga.altitude!,
      altitudeAccuracy: 0,
      heading: rmc.course ?? 0,
      headingAccuracy: 0,
      speed: rmc.speed ?? 0,
      speedAccuracy: 0,
    );
  }

  void clear() {
    _gga = null;
    _rmc = null;
  }
}
