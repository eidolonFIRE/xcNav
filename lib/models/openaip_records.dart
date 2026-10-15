import 'dart:convert';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:objectbox/objectbox.dart';

import 'package:xcnav/models/airport_info.dart';
import 'package:xcnav/models/airspace.dart';

// ObjectBox entities for the OpenAIP cache. Run `dart run build_runner build` after changing these.

/// An area we downloaded OpenAIP data for.
@Entity()
class OpenAipAreaRecord {
  @Id()
  int id = 0;

  double lat;
  double lng;

  /// Meters
  double radius;

  /// Milliseconds since epoch
  int downloadedAt;

  OpenAipAreaRecord(
      {this.id = 0, required this.lat, required this.lng, required this.radius, required this.downloadedAt});

  LatLng get center => LatLng(lat, lng);
}

@Entity()
class AirspaceRecord {
  @Id()
  int id = 0;

  /// OpenAIP `_id`
  @Unique(onConflict: ConflictStrategy.replace)
  String aipId;

  String name;
  int type;
  int icaoClass;

  int lowerValue;
  int lowerUnit;
  int lowerDatum;
  int upperValue;
  int upperUnit;
  int upperDatum;

  /// Outline as [lat, lng, lat, lng, ...]
  Float64List points;

  // Bounding box, for area queries
  double north;
  double south;
  double east;
  double west;

  /// Milliseconds since epoch
  int downloadedAt;

  AirspaceRecord(
      {this.id = 0,
      required this.aipId,
      required this.name,
      required this.type,
      required this.icaoClass,
      required this.lowerValue,
      required this.lowerUnit,
      required this.lowerDatum,
      required this.upperValue,
      required this.upperUnit,
      required this.upperDatum,
      required this.points,
      required this.north,
      required this.south,
      required this.east,
      required this.west,
      required this.downloadedAt});

  factory AirspaceRecord.from(Airspace airspace, DateTime downloadedAt) => AirspaceRecord(
      aipId: airspace.id,
      name: airspace.name,
      type: airspace.type,
      icaoClass: airspace.icaoClass,
      lowerValue: airspace.lower.value,
      lowerUnit: airspace.lower.unit.index,
      lowerDatum: airspace.lower.datum.index,
      upperValue: airspace.upper.value,
      upperUnit: airspace.upper.unit.index,
      upperDatum: airspace.upper.datum.index,
      points: Float64List.fromList(airspace.points.expand((e) => [e.latitude, e.longitude]).toList()),
      north: airspace.bounds.north,
      south: airspace.bounds.south,
      east: airspace.bounds.east,
      west: airspace.bounds.west,
      downloadedAt: downloadedAt.millisecondsSinceEpoch);

  Airspace toAirspace() => Airspace(
      id: aipId,
      name: name,
      type: type,
      icaoClass: icaoClass,
      lower: AltLimit(lowerValue, AltLimitUnit.values[lowerUnit], AltLimitDatum.values[lowerDatum]),
      upper: AltLimit(upperValue, AltLimitUnit.values[upperUnit], AltLimitDatum.values[upperDatum]),
      points: List.generate(points.length ~/ 2, (i) => LatLng(points[i * 2], points[i * 2 + 1])));
}

@Entity()
class AirportRecord {
  @Id()
  int id = 0;

  /// OpenAIP `_id`
  @Unique(onConflict: ConflictStrategy.replace)
  String aipId;

  String name;
  String? code;
  int type;
  double lat;
  double lng;
  double? elevation;
  bool private;

  /// JSON list of [AirportFrequency.toJson]
  String frequencies;

  /// Milliseconds since epoch
  int downloadedAt;

  AirportRecord(
      {this.id = 0,
      required this.aipId,
      required this.name,
      this.code,
      required this.type,
      required this.lat,
      required this.lng,
      this.elevation,
      this.private = false,
      required this.frequencies,
      required this.downloadedAt});

  factory AirportRecord.from(AirportInfo airport, DateTime downloadedAt) => AirportRecord(
      aipId: airport.id,
      name: airport.name,
      code: airport.code,
      type: airport.type,
      lat: airport.latlng.latitude,
      lng: airport.latlng.longitude,
      elevation: airport.elevation,
      private: airport.private,
      frequencies: jsonEncode(airport.frequencies.map((e) => e.toJson()).toList()),
      downloadedAt: downloadedAt.millisecondsSinceEpoch);

  AirportInfo toAirport() => AirportInfo(
      id: aipId,
      name: name,
      code: code,
      type: type,
      latlng: LatLng(lat, lng),
      elevation: elevation,
      private: private,
      frequencies: (jsonDecode(frequencies) as List).map((e) => AirportFrequency.fromJson(e)).toList());
}
