import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/datadog.dart';
import 'package:xcnav/state_geo.dart';
import 'package:xcnav/util.dart';

/// Basic dataclass for holding one immutable weather observation.
class WeatherObservation {
  final double? windSpd;
  final double? windGust;

  /// Compass degrees
  final double? windDir;

  final String stationId;
  final LatLng latlng;
  final DateTime timeObserved;
  final DateTime timeFetched;

  /// Color corrosponding to the wind report.
  late final Color color;

  WeatherObservation(
      this.stationId, this.latlng, this.timeFetched, this.timeObserved, this.windSpd, this.windGust, this.windDir) {
    if ((windSpd ?? 0) > 5.3 || (windGust ?? 0) > 7) {
      // 12mph, g15.6mph
      color = Colors.red.withAlpha(150);
    } else if ((windSpd ?? 0) > 3.6 || (windGust ?? 0) > 4.5) {
      // 8mph, g10mph
      color = Colors.amber.withAlpha(150);
    } else {
      // default
      color = Colors.white.withAlpha(150);
    }
  }
}

/// Basic metadata for a weather station.
class WeatherStation {
  late final String id;
  late final String name;
  late final LatLng latlng;

  bool valid = true;

  DateTime? _fetching;
  WeatherObservation? latestObservation;

  /// Return true if refreshing
  Future<bool> refreshObservation(http.Client client) async {
    if (_fetching != null && _fetching!.isAfter(clock.now().subtract(const Duration(minutes: 1)))) {
      // debugPrint("(WEATHER) Station $id - still fetching (${clock.now().difference(_fetching!)})");
      return false;
    } else {
      _fetching = clock.now();
      // debugPrint("(WEATHER) Station $id - Fetching weather observation for ($id)");

      final response = await client.get(Uri.parse("https://api.weather.gov/stations/$id/observations/latest"),
          headers: {
            "User-Agent": "xcNav.app@gmail.com"
          }).timeout(const Duration(seconds: 30), onTimeout: () => http.Response("", 408));

      // debugPrint("(WEATHER)     - ($id) result ${response.statusCode}");

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        double? windSpd = parseAsDouble(decoded["properties"]["windSpeed"]["value"]);
        double? windGust = parseAsDouble(decoded["properties"]["windGust"]["value"]);
        final double? windDir = parseAsDouble(decoded["properties"]["windDirection"]["value"]);
        final DateTime timeObserved = DateTime.parse(decoded["properties"]["timestamp"]);

        // convert to metric units
        if (decoded["properties"]["windSpeed"]["unitCode"] == "wmoUnit:km_h-1") {
          if (windSpd != null) {
            windSpd = windSpd / 3.6;
          }
          if (windGust != null) {
            windGust = windGust / 3.6;
          }
        }

        latestObservation = WeatherObservation(id, latlng, clock.now(), timeObserved, windSpd, windGust, windDir);
        _fetching = null;
      } else {
        if (response.statusCode == 404) {
          // Mark this station as offline
          valid = false;
        }
        _fetching = null;
      }
      return true;
    }
  }

  Map<String, dynamic> toJson() {
    return {"id": id, "name": name, "lat": latlng.latitude, "lng": latlng.longitude};
  }

  WeatherStation(this.id, this.name, this.latlng);
  WeatherStation.fromJson(dynamic data) {
    id = data["id"];
    name = data["name"];
    latlng = LatLng(parseAsDouble(data["lat"]) ?? 0, parseAsDouble(data["lng"]) ?? 0);
  }
}

/// Singleton class which manages fetching weather observations from ground instruments
/// via the weather.gov mesonets network.
class WeatherObservationService {
  final Map<int, Map<int, Map<String, WeatherStation>>> _stationsByTile = {};

  // ignore: unused_field
  late Timer _serviceLoop;
  late http.Client _client;

  LatLngBounds? mapBounds;

  /// Last time we checked which state we're in.
  DateTime? _lastStateCheck;

  /// Last time we pulled a state's stations.
  final Map<String, DateTime> _lastFetchedByState = {};

  WeatherObservationService() {
    _client = http.Client();
    _serviceLoop = Timer.periodic(const Duration(seconds: 10), _weatherServiceTick);
  }

  /// Reset some long-running rate limit timers
  void resetSomeTimers() {
    _lastStateCheck = null;
  }

  /// Latlng point to a tile. Grid is set to ~22.2km (at equator).
  ///
  /// decimal
  /// places   degrees          distance
  /// -------  -------          --------
  /// 0        1                111  km
  /// 1        0.1              11.1 km
  /// 2        0.01             1.11 km
  /// 3        0.001            111  m
  /// 4        0.0001           11.1 m
  /// 5        0.00001          1.11 m
  /// 6        0.000001         11.1 cm
  /// 7        0.0000001        1.11 cm
  /// 8        0.00000001       1.11 mm
  static Point<int> latlngToCacheTile(LatLng point) {
    int x = (point.latitude * 5).floor();
    int y = (point.longitude * 5).floor();
    return Point<int>(x, y);
  }

  static Iterable<Point<int>> iterTiles(LatLngBounds bounds) sync* {
    final ne = latlngToCacheTile(bounds.northEast);
    final sw = latlngToCacheTile(bounds.southWest);

    final center = Point<int>(((ne.x + sw.x) / 2).floor(), ((ne.y + sw.y) / 2).floor());
    final maxRadius = (ne.y - center.y) + (ne.x - center.x);
    final flatRadius = max(ne.y - center.y, ne.x - center.x);

    // debugPrint("$sw, $center, $ne (radius $maxRadius)");

    yield center;

    // diagonal scan lines of growing radius
    for (int radius = 1; radius <= maxRadius; radius++) {
      // clip the diagonals
      // debugPrint("- r: $radius");
      for (int scan = max(0, radius - flatRadius); scan < min(flatRadius + 1, radius); scan++) {
        // debugPrint("  - s: $scan");
        Point<int> d = Point(radius - scan, scan);

        // Rotate vector 4 times
        for (int t = 0; t < 4; t++) {
          final p = center + d;
          if (p.x >= sw.x && p.x <= ne.x && p.y >= sw.y && p.y <= ne.y) {
            yield p;
          } else {
            // debugPrint("skip $p");
          }

          // rotate
          d = Point(-d.y, d.x);
        }
      }
    }
  }

  /// Iterate through all cached stations inside latlng bounds.
  /// `tileLimit` will only `take` as max count from each tile.
  /// If no limit provided, it will be automatic based on the size of `bounds`.
  Iterable<WeatherStation> iterStations(LatLngBounds bounds,
      {int? tileLimit, bool Function(WeatherStation)? filter}) sync* {
    final limit = tileLimit ?? max(1, (12 / pow(bounds.north - bounds.south, 2)).round());
    for (final tile in iterTiles(bounds)) {
      // debugPrint("(WEATHER) Tile ${tile.x},${tile.y} : ${(_stationsByTile[tile.x]?[tile.y] ?? {}).length}");
      for (final WeatherStation station
          in (_stationsByTile[tile.x]?[tile.y]?.values.where(filter ?? ((e) => true)).take(limit) ?? [])) {
        yield station;
      }
    }
  }

  /// Insert a weather station into correct tile of the cache
  void insertStationToCache(WeatherStation station) {
    final tile = latlngToCacheTile(station.latlng);
    if (_stationsByTile[tile.x] == null) {
      _stationsByTile[tile.x] = {};
    }
    if (_stationsByTile[tile.x]![tile.y] == null) {
      _stationsByTile[tile.x]![tile.y] = {};
    }
    _stationsByTile[tile.x]![tile.y]![station.id] = station;
  }

  Iterable<WeatherObservation> getObservations() sync* {
    if (mapBounds != null) {
      for (final station in iterStations(
        mapBounds!,
        filter: (e) =>
            e.valid &&
            e.latestObservation?.windSpd != null &&
            e.latestObservation!.timeObserved.isAfter(clock.now().subtract(const Duration(minutes: 90))),
      )) {
        yield station.latestObservation!;
      }
    }
  }

  void _saveWeatherStations(String state, List<WeatherStation> stations) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> stationList = [];
    for (final each in stations) {
      stationList.add(jsonEncode(each.toJson()));
    }
    debugPrint("(WEATHER) Saving ${stationList.length} $state weather stations to cache.");
    prefs.setStringList("weatherStationsCache_$state", stationList);
    prefs.setInt("weatherStationsLastFetched_$state", clock.now().millisecondsSinceEpoch);
  }

  void _weatherServiceTick(Timer timer) async {
    // debugPrint("(WEATHER) - tick");

    if (mapBounds == null) {
      // Do nothing
      return;
    }

    if (_lastStateCheck == null || _lastStateCheck!.isBefore(clock.now().subtract(const Duration(minutes: 20)))) {
      _lastStateCheck = clock.now();
      for (final state in checkInsideState(mapBounds!.center)) {
        if (_lastFetchedByState[state] == null) {
          // Placeholder lock
          _lastFetchedByState[state] = clock.now();

          // Get!
          final prefs = await SharedPreferences.getInstance();
          final cache = prefs.getStringList("weatherStationsCache_$state");
          if (cache != null) {
            // ... load from cache
            int count = 0;
            for (final raw in cache) {
              insertStationToCache(WeatherStation.fromJson(jsonDecode(raw)));
              count++;
            }
            debugPrint("(WEATHER) Loaded $count stations from $state cache.");
            _lastFetchedByState[state] = clock.now();
          } else {
            // ... fetch from web
            final fetched = await _fetchStations(_client, state);
            if (fetched != null) {
              int count = 0;
              for (final each in fetched) {
                insertStationToCache(each);
              }
              debugPrint("(WEATHER) Fetched $count stations for $state.");
              _saveWeatherStations(state, fetched);
              _lastFetchedByState[state] = clock.now();
            } else {
              // Reset the lock
              _lastFetchedByState.remove(state);
            }
          }
        }
      }
    }

    // --- Fill station observations
    int countFetched = 0;
    // Refresh if no observation yet, observation is old, or not fetched recently.
    for (final station in iterStations(mapBounds!,
        filter: (e) =>
            e.valid &&
            (e.latestObservation == null ||
                (e.latestObservation!.timeObserved.isBefore(clock.now().subtract(const Duration(minutes: 60))) &&
                    e.latestObservation!.timeFetched.isBefore(clock.now().subtract(const Duration(minutes: 10))))))) {
      countFetched += (await station.refreshObservation(_client)) ? 1 : 0;
      if (countFetched > 20) {
        // Rate limit
        break;
      }
    }
    if (countFetched > 0) {
      debugPrint("(WEATHER) Fetched $countFetched station observations.");
    }
  }
}

/// Fetch weather stations by state code.
///
/// https://www.weather.gov/documentation/services-web-api#/
/// https://weather-gov.github.io/api/general-faqs
Future<List<WeatherStation>?> _fetchStations(http.Client client, String state, {String? cursor}) async {
  final params = {"limit": "500", "state": state};
  if (cursor != null) {
    params["cursor"] = cursor;
  }
  final uri = Uri.https("api.weather.gov", "/stations", params);
  debugPrint("(WEATHER) Fetching stations. URI: $uri");
  final response = await client.get(uri, headers: {"User-Agent": "xcNav.app@gmail.com"}).timeout(
    const Duration(seconds: 60),
    onTimeout: () => http.Response("", 408),
  );
  if (response.statusCode == 200) {
    List<WeatherStation> retval = [];
    final decoded = jsonDecode(response.body);

    for (final station in decoded["features"]) {
      final lat = parseAsDouble(station["geometry"]["coordinates"][1]);
      final lng = parseAsDouble(station["geometry"]["coordinates"][0]);
      if (lat == null || lng == null) {
        continue;
      }
      final latlng = LatLng(lat, lng);
      final name = station["properties"]["name"];
      final id = station["properties"]["stationIdentifier"];
      retval.add(WeatherStation(id, name, latlng));
      // debugPrint("(WEATHER)\t- $id $name $latlng");
    }
    debugPrint("(WEATHER) - Got ${retval.length} weather stations (cursor: $cursor)");

    if (decoded["pagination"]?["next"] != null && retval.isNotEmpty) {
      // Fetch next page
      final nextCursor = Uri.parse(decoded["pagination"]?["next"]).queryParameters["cursor"];
      if (nextCursor != null && nextCursor != cursor) {
        debugPrint("(WEATHER) Next Page: $nextCursor");

        final nextFetch = await _fetchStations(client, state, cursor: nextCursor);
        if (nextFetch != null) {
          retval.addAll(nextFetch);
        } else {
          error("Failed to finish fetching weather stations for: $uri");
          return null;
        }
      }
    }

    return retval;
  } else {
    // failed
    error("Failed (${response.statusCode}) to fetch WeatherStations for: $uri");
    return null;
  }
}

// (DEBUG)
// List<LatLng> tileToLatLngs(Point<int> tile) {
//   return [
//     LatLng(tile.x / 5, tile.y / 5),
//     LatLng((tile.x + 1) / 5, tile.y / 5),
//     LatLng((tile.x + 1) / 5, (tile.y + 1) / 5),
//     LatLng(tile.x / 5, (tile.y + 1) / 5),
//   ];
// }

/// Global (private) singleton
WeatherObservationService? _weatherService;

void weatherServiceResetSomeTimers() {
  _weatherService?.resetSomeTimers();
}

Iterable<WeatherObservation> getWeatherObservations(LatLngBounds bounds) {
  _weatherService ??= WeatherObservationService();

  _weatherService?.mapBounds = bounds;

  return _weatherService?.getObservations() ?? [];
}
