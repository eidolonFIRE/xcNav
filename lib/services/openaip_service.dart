import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/datadog.dart';
import 'package:xcnav/models/airport_info.dart';
import 'package:xcnav/models/airspace.dart';
import 'package:xcnav/secrets.dart';
import 'package:xcnav/services/openaip_store.dart';
import 'package:xcnav/util.dart';

/// Loads airspace and airports around the pilot from the OpenAIP core API (v2).
///
/// Downloads are kept in an ObjectBox database ([OpenAipStore]) that grows as the pilot flies new areas, so the data
/// is available offline and between app uses.
///
/// https://docs.openaip.net/?urls.primaryName=Core%20API
class OpenAipService with ChangeNotifier {
  static const _apiUrl = "https://api.core.openaip.net/api";

  /// Database folder in the app documents directory
  static const _dbFolder = "openaip";

  /// Fetch radius around the pilot
  static const fetchRadius = 150000.0;

  /// Refetch once we're this far from the center of every fresh download
  static const refetchDistance = 75000.0;

  /// Downloads are refreshed after this long. (Old data is still used if the refresh fails.)
  static const maxAge = Duration(days: 30);

  /// Wait after a failed download. Doubles on each failure, up to [maxRetryInterval].
  static const retryInterval = Duration(minutes: 10);
  static const maxRetryInterval = Duration(hours: 2);
  static const _nextAttemptKey = "openaip.nextAttempt";

  /// The API rate limit (429) clears within seconds, so retry a request a few times before giving up.
  static const _rateLimitRetries = 3;

  /// Load cached items this far around the pilot into memory
  static const loadRadius = 150000.0;

  /// Reload from the database once we're this far from the last load center
  static const reloadDistance = 25000.0;

  static const _pageLimit = 1000;
  static const _maxPages = 10;

  final String apiKey;
  final http.Client? _client;

  /// Wait before retrying a rate limited (429) request
  final Duration rateLimitWait;

  OpenAipStore? _store;

  /// Defaults to an in-memory store until [init] opens the database.
  OpenAipStore get store => _store ??= MemoryOpenAipStore();

  /// Relevant airspaces near the pilot, ready to draw
  List<Airspace> airspaces = [];

  /// Relevant airports near the pilot, ready to draw
  List<AirportInfo> airports = [];

  LatLng? _loadedCenter;
  bool _busy = false;

  /// Don't download before this. (Persisted so app restarts don't hammer the API after a failure.)
  DateTime? _nextAttempt;
  Duration _retryDelay = retryInterval;

  /// From the `Retry-After` header of a 429 response
  Duration? _retryAfter;

  OpenAipService(
      {String? apiKey, http.Client? client, OpenAipStore? store, this.rateLimitWait = const Duration(seconds: 10)})
      : apiKey = apiKey ?? aipClientToken,
        _client = client,
        _store = store;

  bool get _hasKey => apiKey.isNotEmpty && apiKey != "unset";

  /// Open the database. Falls back to an in-memory cache if it can't be opened.
  Future init() async {
    try {
      final next = (await SharedPreferences.getInstance()).getInt(_nextAttemptKey);
      if (next != null) _nextAttempt = DateTime.fromMillisecondsSinceEpoch(next);
    } catch (err, trace) {
      error("Couldn't load OpenAIP retry time", errorMessage: err.toString(), errorStackTrace: trace);
    }
    if (_store != null) return;
    try {
      _store = await ObjectBoxOpenAipStore.open("${(await getApplicationDocumentsDirectory()).path}/$_dbFolder");
      debugPrint("OpenAIP cache: ${store.airspaceCount} airspaces, ${store.airportCount} airports, "
          "${store.areaCount} areas.");
    } catch (err, trace) {
      error("Couldn't open OpenAIP database", errorMessage: err.toString(), errorStackTrace: trace);
      _store = MemoryOpenAipStore();
    }
  }

  /// Cheap to call often. Loads from the database when the pilot has moved, and downloads from OpenAIP when there's
  /// no fresh download near [center].
  Future refresh(LatLng center) async {
    if (_busy) return;
    _busy = true;
    try {
      // Callers are often in build(), so don't notify listeners synchronously.
      await Future.microtask(() {});
      if (_loadedCenter == null || latlngCalc.distance(_loadedCenter!, center) > reloadDistance) {
        _load(center);
      }
      if (!_hasKey) return;
      if (store.areaNear(center, refetchDistance, clock.now().subtract(maxAge)) != null) return;
      if (_nextAttempt != null && clock.now().isBefore(_nextAttempt!)) return;

      final client = _client ?? http.Client();
      try {
        // One after the other, to go easy on the API rate limit.
        final fetchedAirspaces = await fetchAirspaces(center, client: client);
        final fetchedAirports = fetchedAirspaces != null ? await fetchAirports(center, client: client) : null;
        if (fetchedAirspaces == null || fetchedAirports == null) {
          _backOff();
        } else {
          _retryDelay = retryInterval;
          _setNextAttempt(null);
          debugPrint("Fetched ${fetchedAirspaces.length} airspaces, ${fetchedAirports.length} airports.");
          store.putDownload(
              center: center,
              radius: fetchRadius,
              downloadedAt: clock.now(),
              // Store everything, so changes to what's relevant apply to cached data too.
              airspaces: fetchedAirspaces,
              airports: fetchedAirports);
          _load(center);
        }
      } finally {
        if (_client == null) client.close();
      }
    } catch (err, trace) {
      error("OpenAIP refresh failed", errorMessage: err.toString(), errorStackTrace: trace);
      _backOff();
    } finally {
      _busy = false;
    }
  }

  /// Wait longer after each failure, or as long as the server asks.
  void _backOff() {
    final retryAfter = _retryAfter;
    _retryAfter = null;
    final delay = retryAfter != null && retryAfter > _retryDelay ? retryAfter : _retryDelay;
    _retryDelay = _retryDelay * 2 > maxRetryInterval ? maxRetryInterval : _retryDelay * 2;
    debugPrint("OpenAIP: retry in ${delay.inMinutes} min");
    _setNextAttempt(clock.now().add(delay));
  }

  void _setNextAttempt(DateTime? time) {
    _nextAttempt = time;
    SharedPreferences.getInstance().then((prefs) {
      if (time == null) {
        prefs.remove(_nextAttemptKey);
      } else {
        prefs.setInt(_nextAttemptKey, time.millisecondsSinceEpoch);
      }
    }).catchError((err, trace) {
      error("Couldn't save OpenAIP retry time", errorMessage: err.toString(), errorStackTrace: trace);
    });
  }

  /// Pull cached items around [center] from the database
  void _load(LatLng center) {
    final bounds = LatLngBoundsSimple.around(center, loadRadius);
    airspaces = store.airspacesIn(bounds).where((e) => e.isRelevant).toList();
    airports = store.airportsIn(bounds).where((e) => e.isRelevant).toList();
    _loadedCenter = center;
    notifyListeners();
  }

  /// Delete all cached OpenAIP data
  void clear() {
    store.clear();
    airspaces = [];
    airports = [];
    _loadedCenter = null;
    _retryDelay = retryInterval;
    _setNextAttempt(null);
    notifyListeners();
  }

  /// Airspaces containing [point]
  List<Airspace> airspacesAt(LatLng point) => airspaces.where((e) => e.containsPoint(point)).toList();

  /// Fetch all pages of airspace around [center]. Returns null on failure.
  Future<List<Airspace>?> fetchAirspaces(LatLng center, {http.Client? client}) =>
      _fetchAll("airspaces", center, Airspace.fromOpenAip, client: client);

  /// Fetch all pages of airports around [center]. Returns null on failure.
  Future<List<AirportInfo>?> fetchAirports(LatLng center, {http.Client? client}) =>
      _fetchAll("airports", center, AirportInfo.fromOpenAip, client: client);

  Future<List<T>?> _fetchAll<T extends Object>(String endpoint, LatLng center, T? Function(Map<String, dynamic>) parse,
      {http.Client? client}) async {
    final httpClient = client ?? _client ?? http.Client();
    try {
      final List<T> results = [];
      int? page = 1;
      for (int i = 0; i < _maxPages && page != null; i++) {
        final uri = Uri.parse("$_apiUrl/$endpoint").replace(queryParameters: {
          "pos": "${center.latitude.toStringAsFixed(4)},${center.longitude.toStringAsFixed(4)}",
          "dist": fetchRadius.round().toString(),
          "limit": _pageLimit.toString(),
          "page": page.toString(),
        });
        var response = await httpClient.get(uri, headers: {"x-openaip-api-key": apiKey, "Accept": "application/json"});
        for (int retry = 1;
            retry <= _rateLimitRetries && response.statusCode == 429 && response.headers["retry-after"] == null;
            retry++) {
          debugPrint("OpenAIP: rate limited ($endpoint), retry $retry");
          await Future.delayed(rateLimitWait * retry);
          response = await httpClient.get(uri, headers: {"x-openaip-api-key": apiKey, "Accept": "application/json"});
        }
        if (response.statusCode != 200) {
          if (response.statusCode == 429) {
            final seconds = int.tryParse(response.headers["retry-after"] ?? "");
            if (seconds != null) _retryAfter = Duration(seconds: seconds);
          }
          error("OpenAIP fetch failed", errorMessage: "HTTP ${response.statusCode} ($endpoint)", attributes: {
            "endpoint": endpoint,
            "statusCode": response.statusCode.toString(),
            "body": response.body.length > 300 ? response.body.substring(0, 300) : response.body,
          });
          return null;
        }
        // Pages can be several MB, so parse off the UI thread.
        final parsed = await compute(_parsePage<T>, (body: response.body, parse: parse));
        results.addAll(parsed.items);
        // `nextPage` isn't always given, so a full page also means there could be more.
        if (parsed.nextPage != null && parsed.nextPage != page) {
          page = parsed.nextPage;
        } else {
          page = parsed.itemCount >= _pageLimit ? page + 1 : null;
        }
      }
      return results;
    } catch (err, trace) {
      error("OpenAIP fetch failed",
          errorMessage: err.toString(), errorStackTrace: trace, attributes: {"endpoint": endpoint});
      return null;
    } finally {
      if (client == null && _client == null) httpClient.close();
    }
  }
}

({List<T> items, int? nextPage, int itemCount}) _parsePage<T extends Object>(
    ({String body, T? Function(Map<String, dynamic>) parse}) args) {
  final data = jsonDecode(args.body);
  final items = data["items"] as List? ?? [];
  return (
    items: items.whereType<Map<String, dynamic>>().map(args.parse).nonNulls.toList(),
    nextPage: data["nextPage"] is int ? data["nextPage"] : null,
    itemCount: items.length,
  );
}

final openAipService = OpenAipService();
