import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/datadog.dart';
import 'package:xcnav/util.dart';

class WeatherObservation {
  final double? windSpd;
  final double? windGust;

  /// Compass degrees
  final double? windDir;

  final String stationId;
  final LatLng latlng;
  final DateTime timeObserved;
  final DateTime timeFetched;

  WeatherObservation(
      this.stationId, this.latlng, this.timeFetched, this.timeObserved, this.windSpd, this.windGust, this.windDir);
}

class WeatherStation {
  late final String id;
  late final String name;
  late final LatLng latlng;

  DateTime? _fetching;
  WeatherObservation? latestObservation;

  /// Return true if refreshing
  Future<bool> refreshObservation(http.Client client) async {
    if (_fetching != null && _fetching!.isAfter(clock.now().subtract(const Duration(minutes: 1)))) {
      debugPrint("(WEATHER) Station $id - still fetching (${clock.now().difference(_fetching!)})");
      return false;
    } else {
      _fetching = clock.now();
      debugPrint("(WEATHER) Station $id - Fetching weather observation for ($id)");

      final response = await client.get(Uri.parse("https://api.weather.gov/stations/$id/observations/latest"),
          headers: {
            "User-Agent": "xcNav.app@gmail.com"
          }).timeout(const Duration(seconds: 30), onTimeout: () => http.Response("", 408));

      debugPrint("(WEATHER)     - ($id) result ${response.statusCode}");

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final double? windSpd = parseAsDouble(decoded["properties"]["windSpeed"]["value"]);
        // TODO: to get gust data, will need to look back at the few previous observations
        final double? windGust = parseAsDouble(decoded["properties"]["windGust"]["value"]);
        final double? windDir = parseAsDouble(decoded["properties"]["windDirection"]["value"]);
        final DateTime timeObserved = DateTime.parse(decoded["properties"]["timestamp"]);
        latestObservation = WeatherObservation(id, latlng, clock.now(), timeObserved, windSpd, windGust, windDir);
        _fetching = null;
      } else {
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

class WeatherTile {
  late final int x;
  late final int y;

  /// Weather Forecast Office
  late final String wfo;

  final LatLng? fromPoint;

  WeatherTile(this.x, this.y, this.wfo, {this.fromPoint});

  static Future<WeatherTile?> fetch(http.Client client, LatLng point) async {
    final uri = Uri.https(
        "api.weather.gov", "/points/${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}");
    debugPrint("(WEATHER) Fetching tile. $uri");
    final response = await client.get(uri, headers: {"User-Agent": "xcNav.app@gmail.com"}).timeout(
      const Duration(seconds: 10),
      onTimeout: () => http.Response("", 408),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final x = parseAsInt(decoded["properties"]["gridX"]);
      final y = parseAsInt(decoded["properties"]["gridY"]);
      final wfo = parseAsString(decoded["properties"]["gridId"]);
      if (x != null && y != null && wfo != null) {
        return WeatherTile(x, y, wfo, fromPoint: point);
      }
    } else {
      error("Failed to fetch weather grid tile. (${response.statusCode})");
    }
    return null;
  }

  @override
  String toString() {
    return "WeatherTile ($x, $y) $wfo, $fromPoint";
  }
}

///==========================================================================================================================
///
///
///
/// https://www.weather.gov/documentation/services-web-api#/
/// https://weather-gov.github.io/api/general-faqs
///
///
/// 1. Latlng -> grid point and wfo: https://api.weather.gov/points/37.065921%2C-121.603350
/// 2. Grid and wfo -> to station list: https://api.weather.gov/gridpoints/MTR/107,68/stations?limit=500
/// 3. Stations -> latest observation: https://api.weather.gov/stations/WFT19066/observations/latest
/// 3b. Stations -> multiple observations to get gust data: https://api.weather.gov/stations/WFT19066/observations?limit=5
///
///
/// Main loop tick:
///   - Check if latest request Latlng has drifted 1km
///     - get grid point for new LatLng
///     - Fetch stations for 3x3 grids around the point (and cache)
///       -
///

// GLOBALS

/// Grid size in meters
const double _TILE_SIZE = 2500;

WeatherObservationService? _weatherService;

class WeatherObservationService {
  /// Latest weather tile for the current map view
  WeatherTile? centerTile;

  final Map<int, Map<int, WeatherTile>> _tileCache = {};
  final Map<int, Map<int, List<WeatherStation>>> _stations = {};

  late Timer _serviceLoop;
  late http.Client _client;
  late final SharedPreferences? _prefs;

  LatLng? _mapCenter;
  double _mapRadius = 0;

  WeatherObservationService() {
    _client = http.Client();
    SharedPreferences.getInstance().then((value) => _prefs = value);
    _serviceLoop = Timer.periodic(const Duration(seconds: 10), _weatherServiceTick);
  }

  /// Track what the user is looking at on map
  void updateMap(LatLng center, double radius) {
    _mapCenter = center;
    _mapRadius = radius;
  }

  List<WeatherObservation> getObservations() {
    if (centerTile != null && _stations[centerTile!.x]?[centerTile!.y] != null) {
      List<WeatherObservation> retval = [];
      for (final WeatherStation station in _stations[centerTile!.x]?[centerTile!.y] ?? []) {
        if (station.latestObservation?.windSpd != null &&
            station.latestObservation!.timeObserved.isAfter(clock.now().subtract(const Duration(hours: 3)))) {
          retval.add(station.latestObservation!);
        }
      }
      return retval;
    }
    return [];
  }

  void _tileCacheInsert(WeatherTile tile) {
    if (_tileCache[tile.x] == null) {
      _tileCache[tile.x] = {};
    }
    _tileCache[tile.x]![tile.y] = tile;
    // TODO: save cache
  }

  void _stationCacheInsert(WeatherTile tile, List<WeatherStation> stations) {
    if (_stations[tile.x] == null) {
      _stations[tile.x] = {};
    }
    _stations[tile.x]![tile.y] = stations;
    // TODO: save cache
  }

  void _weatherServiceTick(Timer timer) async {
    debugPrint("(WEATHER) - tick");

    if (_mapCenter == null) {
      // Do nothing
      return;
    }

    // --- Update current grid
    if (centerTile?.fromPoint == null || latlngCalc.distance(centerTile!.fromPoint!, _mapCenter!) >= _TILE_SIZE / 2) {
      // Update center tile

      final response = await WeatherTile.fetch(_client, _mapCenter!);
      if (response != null) {
        debugPrint("(WEATHER) $response");
        centerTile = response;
        _tileCacheInsert(centerTile!);
      }
    }

    // --- Fill tile stations
    if (centerTile != null && _stations[centerTile!.x]?[centerTile!.y] == null) {
      final response = await _fetchStations(_client, centerTile!);
      if (response != null) {
        _stationCacheInsert(centerTile!, response);
      }
    }

    // --- Fill station observations
    if (centerTile != null) {
      int countFetched = 0;
      for (final WeatherStation station in _stations[centerTile!.x]?[centerTile!.y] ?? []) {
        if (station.latestObservation == null ||
            (station.latestObservation!.timeObserved.isBefore(clock.now().subtract(const Duration(minutes: 90))) &&
                station.latestObservation!.timeFetched.isBefore(clock.now().subtract(const Duration(minutes: 10))))) {
          countFetched += (await station.refreshObservation(_client)) ? 1 : 0;
          if (countFetched > 10) {
            // Rate limit
            break;
          }
        }
      }
    }
  }
}

// void saveWeatherStations(String state) async {
//   final prefs = await SharedPreferences.getInstance();
//   final List<String> stationList = [];
//   for (final each in _stationsByState[state] ?? []) {
//     stationList.add(jsonEncode(each.toJson()));
//   }
//   debugPrint("(WEATHER)Saving ${stationList.length} weather stations to cache.");
//   prefs.setStringList("weatherStationsCache_$state", stationList);
//   prefs.setInt("weatherStationsLastFetched_$state", clock.now().millisecondsSinceEpoch);
// }

// void refreshWeatherStations(String state) async {
//   final prefs = await SharedPreferences.getInstance();

//   // Try pulling from cache
//   final cacheRawTime = prefs.getInt("weatherStationsLastFetched_$state");
//   var cacheTimestamp = cacheRawTime != null ? DateTime.fromMillisecondsSinceEpoch(cacheRawTime) : null;

//   // Don't load cache if it's older than what we have
//   if (cacheTimestamp != null &&
//       (_fetchTimeByState[state] == null || _fetchTimeByState[state]!.isBefore(cacheTimestamp))) {
//     final cache = prefs.getStringList("weatherStationsCache_$state");
//     if (cache != null) {
//       // Load from cache
//       _stationsByState[state] = cache.map((e) => WeatherStation.fromJson(jsonDecode(e))).toList();
//       debugPrint("(WEATHER) Loaded ${_stationsByState[state]!.length} weather stations from cache.");
//     } else {
//       // Clear this so we try to fetch
//       prefs.remove("weatherStationsLastFetched_$state");
//       error("Failed to load weather stations from cache for $state");
//     }
//   }

//   // If no cache, or cache is old, try to refresh
//   if (cacheTimestamp == null || cacheTimestamp.isBefore(clock.now().subtract(const Duration(hours: 1)))) {
//     // If we haven't tried fetching, or it's been 2 minutes
//     if (_fetchTimeByState[state] == null ||
//         _fetchTimeByState[state]!.isBefore(clock.now().subtract(const Duration(minutes: 2)))) {
//       // Mutex to block next attempt
//       _fetchTimeByState[state] = clock.now();
//       final response = await _fetchStations(state);

//       if (response != null && response.isNotEmpty) {
//         _stationsByState[state] = response;
//         saveWeatherStations(state);
//       }
//     } else {
//       debugPrint(
//           "...skipping fetch of Weather Stations. Last request ${clock.now().difference(_fetchTimeByState[state]!)}");
//     }
//   }
// }

Future<List<WeatherStation>?> _fetchStations(http.Client client, WeatherTile tile, {String? cursor}) async {
  final params = {"limit": "500"};
  if (cursor != null) {
    params["cursor"] = cursor;
  }
  final uri = Uri.https("api.weather.gov", "/gridpoints/${tile.wfo}/${tile.x},${tile.y}/stations", params);
  debugPrint("(WEATHER) Fetching stations. URI: $uri");
  final response = await client.get(uri, headers: {"User-Agent": "xcNav.app@gmail.com"}).timeout(
    const Duration(seconds: 20),
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

    if (decoded["pagination"]?["next"] != null) {
      // Fetch next page
      final nextCursor = Uri.parse(decoded["pagination"]?["next"]).queryParameters["cursor"];
      if (nextCursor != null && nextCursor != cursor) {
        debugPrint("Next Page: $nextCursor");

        final nextFetch = await _fetchStations(client, tile, cursor: nextCursor);
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

///==========================================================================================================================
///
///   PUBLIC
///
///
///
///
///
///
///
///

List<WeatherObservation> getWeatherObservations(LatLng center, double radius) {
  _weatherService ??= WeatherObservationService();

  _weatherService?.updateMap(center, radius);

  // final stations = _stationsByState[state];

  return _weatherService?.getObservations() ?? [];

  // if (stations != null) {
  //   debugPrint("(WEATHER) Gathering from ${stations.length} stations");

  //   List<WeatherObservation> retval = [];

  //   int count = 0;
  //   for (final eachStation in stations) {
  //     if (latlngCalc.distance(eachStation.latlng, center) <= radius) {
  //       count++;
  //       // Don't show old observations
  //       if (eachStation.latestObservation != null &&
  //           eachStation.latestObservation!.timeObserved.isAfter(clock.now().subtract(const Duration(hours: 4)))) {
  //         if (eachStation.latestObservation!.windSpd != null && eachStation.latestObservation!.windDir != null) {
  //           retval.add(eachStation.latestObservation!);
  //         }
  //       }
  //     }
  //   }

  //   debugPrint("(WEATHER) - Got ${retval.length}/$count observations");

  //   return retval;
  // } else {
  //   debugPrint("(WEATHER) No stations loaded for $state");
  //   return [];
  // }
}
