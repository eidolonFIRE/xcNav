import 'package:latlong2/latlong.dart';

import 'package:xcnav/models/airport_info.dart';
import 'package:xcnav/models/airspace.dart';
import 'package:xcnav/models/openaip_records.dart';
import 'package:xcnav/objectbox.g.dart';
import 'package:xcnav/util.dart';

/// Persistent cache of OpenAIP data. It grows as new areas are downloaded.
abstract class OpenAipStore {
  /// Most recent download covering [center] (within [maxDistance] of its center) that is newer than [since].
  OpenAipAreaRecord? areaNear(LatLng center, double maxDistance, DateTime since);

  /// Save one download. Items in the area that are older than this download, but weren't in it, have been removed
  /// from OpenAIP, so they're deleted.
  void putDownload(
      {required LatLng center,
      required double radius,
      required DateTime downloadedAt,
      required List<Airspace> airspaces,
      required List<AirportInfo> airports});

  List<Airspace> airspacesIn(LatLngBoundsSimple bounds);

  List<AirportInfo> airportsIn(LatLngBoundsSimple bounds);

  int get airspaceCount;
  int get airportCount;
  int get areaCount;

  void clear();

  void close();
}

/// Whether [bounds] lies completely inside the circle.
bool _boundsInCircle(LatLngBoundsSimple bounds, LatLng center, double radius) => [
      LatLng(bounds.north, bounds.east),
      LatLng(bounds.north, bounds.west),
      LatLng(bounds.south, bounds.east),
      LatLng(bounds.south, bounds.west),
    ].every((p) => latlngCalc.distance(center, p) <= radius);

/// Whether an older area is completely covered by a newer one, so its record isn't needed anymore.
bool _areaCovered(OpenAipAreaRecord old, LatLng center, double radius) =>
    latlngCalc.distance(old.center, center) + old.radius <= radius;

class ObjectBoxOpenAipStore implements OpenAipStore {
  final Store store;
  late final Box<OpenAipAreaRecord> _areas = store.box();
  late final Box<AirspaceRecord> _airspaces = store.box();
  late final Box<AirportRecord> _airports = store.box();

  ObjectBoxOpenAipStore(this.store);

  /// Open (or create) the database in [directory].
  static Future<ObjectBoxOpenAipStore> open(String directory) async =>
      ObjectBoxOpenAipStore(await openStore(directory: directory));

  @override
  OpenAipAreaRecord? areaNear(LatLng center, double maxDistance, DateTime since) {
    final query = _areas
        .query(OpenAipAreaRecord_.downloadedAt.greaterOrEqual(since.millisecondsSinceEpoch))
        .order(OpenAipAreaRecord_.downloadedAt, flags: Order.descending)
        .build();
    try {
      return query.find().where((e) => latlngCalc.distance(e.center, center) < maxDistance).firstOrNull;
    } finally {
      query.close();
    }
  }

  @override
  void putDownload(
      {required LatLng center,
      required double radius,
      required DateTime downloadedAt,
      required List<Airspace> airspaces,
      required List<AirportInfo> airports}) {
    final time = downloadedAt.millisecondsSinceEpoch;
    final area = LatLngBoundsSimple.around(center, radius);
    store.runInTransaction(TxMode.write, () {
      _airspaces.putMany(airspaces.map((e) => AirspaceRecord.from(e, downloadedAt)).toList());
      _airports.putMany(airports.map((e) => AirportRecord.from(e, downloadedAt)).toList());

      // --- Remove what OpenAIP doesn't have anymore
      final staleAirspaces = _airspaces
          .query(AirspaceRecord_.downloadedAt
              .lessThan(time)
              .and(AirspaceRecord_.north.lessOrEqual(area.north))
              .and(AirspaceRecord_.south.greaterOrEqual(area.south))
              .and(AirspaceRecord_.east.lessOrEqual(area.east))
              .and(AirspaceRecord_.west.greaterOrEqual(area.west)))
          .build();
      _airspaces.removeMany(staleAirspaces
          .find()
          .where((e) => _boundsInCircle(LatLngBoundsSimple(e.north, e.south, e.east, e.west), center, radius))
          .map((e) => e.id)
          .toList());
      staleAirspaces.close();

      final staleAirports = _airports
          .query(AirportRecord_.downloadedAt
              .lessThan(time)
              .and(AirportRecord_.lat.between(area.south, area.north))
              .and(AirportRecord_.lng.between(area.west, area.east)))
          .build();
      _airports.removeMany(staleAirports
          .find()
          .where((e) => latlngCalc.distance(LatLng(e.lat, e.lng), center) <= radius)
          .map((e) => e.id)
          .toList());
      staleAirports.close();

      // --- Record the area
      _areas.removeMany(_areas.getAll().where((e) => _areaCovered(e, center, radius)).map((e) => e.id).toList());
      _areas.put(OpenAipAreaRecord(lat: center.latitude, lng: center.longitude, radius: radius, downloadedAt: time));
    });
  }

  @override
  List<Airspace> airspacesIn(LatLngBoundsSimple bounds) {
    final query = _airspaces
        .query(AirspaceRecord_.north
            .greaterOrEqual(bounds.south)
            .and(AirspaceRecord_.south.lessOrEqual(bounds.north))
            .and(AirspaceRecord_.east.greaterOrEqual(bounds.west))
            .and(AirspaceRecord_.west.lessOrEqual(bounds.east)))
        .build();
    try {
      return query.find().map((e) => e.toAirspace()).toList();
    } finally {
      query.close();
    }
  }

  @override
  List<AirportInfo> airportsIn(LatLngBoundsSimple bounds) {
    final query = _airports
        .query(AirportRecord_.lat
            .between(bounds.south, bounds.north)
            .and(AirportRecord_.lng.between(bounds.west, bounds.east)))
        .build();
    try {
      return query.find().map((e) => e.toAirport()).toList();
    } finally {
      query.close();
    }
  }

  @override
  int get airspaceCount => _airspaces.count();
  @override
  int get airportCount => _airports.count();
  @override
  int get areaCount => _areas.count();

  @override
  void clear() {
    store.runInTransaction(TxMode.write, () {
      _areas.removeAll();
      _airspaces.removeAll();
      _airports.removeAll();
    });
  }

  @override
  void close() => store.close();
}

/// Not persisted. Used when the database can't be opened, and in tests.
class MemoryOpenAipStore implements OpenAipStore {
  final List<OpenAipAreaRecord> _areas = [];
  final Map<String, ({Airspace airspace, int downloadedAt})> _airspaces = {};
  final Map<String, ({AirportInfo airport, int downloadedAt})> _airports = {};

  @override
  OpenAipAreaRecord? areaNear(LatLng center, double maxDistance, DateTime since) => (_areas.toList()
        ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt)))
      .where(
          (e) => e.downloadedAt >= since.millisecondsSinceEpoch && latlngCalc.distance(e.center, center) < maxDistance)
      .firstOrNull;

  @override
  void putDownload(
      {required LatLng center,
      required double radius,
      required DateTime downloadedAt,
      required List<Airspace> airspaces,
      required List<AirportInfo> airports}) {
    final time = downloadedAt.millisecondsSinceEpoch;
    _airspaces.removeWhere((_, e) => e.downloadedAt < time && _boundsInCircle(e.airspace.bounds, center, radius));
    _airports.removeWhere((_, e) => e.downloadedAt < time && latlngCalc.distance(e.airport.latlng, center) <= radius);
    for (final each in airspaces) {
      _airspaces[each.id] = (airspace: each, downloadedAt: time);
    }
    for (final each in airports) {
      _airports[each.id] = (airport: each, downloadedAt: time);
    }
    _areas.removeWhere((e) => _areaCovered(e, center, radius));
    _areas.add(OpenAipAreaRecord(lat: center.latitude, lng: center.longitude, radius: radius, downloadedAt: time));
  }

  @override
  List<Airspace> airspacesIn(LatLngBoundsSimple bounds) =>
      _airspaces.values.map((e) => e.airspace).where((e) => e.bounds.overlaps(bounds)).toList();

  @override
  List<AirportInfo> airportsIn(LatLngBoundsSimple bounds) =>
      _airports.values.map((e) => e.airport).where((e) => bounds.contains(e.latlng)).toList();

  @override
  int get airspaceCount => _airspaces.length;
  @override
  int get airportCount => _airports.length;
  @override
  int get areaCount => _areas.length;

  @override
  void clear() {
    _areas.clear();
    _airspaces.clear();
    _airports.clear();
  }

  @override
  void close() {}
}
