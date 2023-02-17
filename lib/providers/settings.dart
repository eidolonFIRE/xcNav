import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:xcnav/dem_service.dart';

import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/secrets.dart';
import 'package:xcnav/units.dart';

class Settings with ChangeNotifier {
  // --- Map TileProviders
  String _curMapTiles = "topo";
  final Map<String, double> _mapOpacity = {
    "topo": 1.0,
    "sectional": 1.0,
    "satellite": 1.0,
    "airspace": 1.0,
    "airports": 1.0,
  };

  TileProvider? makeTileProvider(instanceName) {
    return FMTC.instance(instanceName).getTileProvider(
          FMTCTileProviderSettings(
            behavior: CacheBehavior.cacheFirst,
            cachedValidDuration: const Duration(days: 14),
          ),
        );
  }

  TileLayer getMapTileLayer(String name, {double? opacity}) {
    switch (name) {
      case "sectional":
        return TileLayer(
            urlTemplate: 'http://wms.chartbundle.com/tms/v1.0/sec/{z}/{x}/{y}.png?type=google',
            tileProvider: makeTileProvider(name),
            maxNativeZoom: 13,
            minZoom: 4,
            opacity: (opacity ?? _mapOpacity["sectional"] ?? 1.0) * 0.8 + 0.2);
      case "satellite":
        return TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            tileProvider: makeTileProvider(name),
            maxNativeZoom: 19,
            opacity: (opacity ?? _mapOpacity["satellite"] ?? 1.0) * 0.8 + 0.2);
      // https://docs.openaip.net/?urls.primaryName=Tiles%20API
      case "airspace":
        return TileLayer(
            urlTemplate: 'https://api.tiles.openaip.net/api/data/airspaces/{z}/{x}/{y}.png?apiKey={apiKey}',
            tileProvider: makeTileProvider(name),
            backgroundColor: Colors.transparent,
            // maxZoom: 11,
            maxNativeZoom: 11,
            minZoom: 7,
            additionalOptions: const {"apiKey": aipClientToken});
      case "airports":
        return TileLayer(
            urlTemplate: 'https://api.tiles.openaip.net/api/data/airports/{z}/{x}/{y}.png?apiKey={apiKey}',
            tileProvider: makeTileProvider(name),
            backgroundColor: Colors.transparent,
            maxZoom: 11,
            minZoom: 9,
            additionalOptions: const {"apiKey": aipClientToken});
      default:
        return TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
          // urlTemplate: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png", // Use this line to test seeing the elevation map
          tileProvider: makeTileProvider(name),
          opacity: opacity ?? 1.0,
        );
    }
  }

  static final Map<String, Image> mapTileThumbnails = {
    "topo": Image.asset(
      "assets/images/topo.png",
      filterQuality: FilterQuality.high,
      fit: BoxFit.cover,
    ),
    "sectional": Image.asset(
      "assets/images/sectional.png",
      filterQuality: FilterQuality.high,
      fit: BoxFit.cover,
    ),
    "satellite": Image.asset(
      "assets/images/satellite.png",
      filterQuality: FilterQuality.high,
      fit: BoxFit.cover,
    ),
    "airspace": Image.asset(
      "assets/images/sectional.png",
      filterQuality: FilterQuality.high,
      fit: BoxFit.cover,
    ),
    "airports": Image.asset(
      "assets/images/sectional.png",
      filterQuality: FilterQuality.high,
      fit: BoxFit.cover,
    )
  };

  // --- Modes
  bool _groundMode = false;
  bool _groundModeTelemetry = false;

  // --- Debug Tools
  bool _spoofLocation = false;

  // --- UI
  bool _mapControlsRightSide = false;
  bool _showPilotNames = false;
  bool _northlockMap = false;
  bool _northlockWind = false;
  bool _showWeatherOverlay = true;
  bool _showAirspaceOverlay = true;

  // --- Units
  var _displayUnitsSpeed = DisplayUnitsSpeed.mph;
  var _displayUnitsVario = DisplayUnitsVario.fpm;
  var _displayUnitsDist = DisplayUnitsDist.imperial;
  var _displayUnitsFuel = DisplayUnitsFuel.liter;

  // --- ADSB
  final Map<String, ProximityConfig> proximityProfileOptions = {
    "Off": ProximityConfig(vertical: 0, horizontalDist: 0, horizontalTime: 0),
    "Small": ProximityConfig(vertical: 200, horizontalDist: 600, horizontalTime: 30),
    "Medium": ProximityConfig(vertical: 400, horizontalDist: 1200, horizontalTime: 45),
    "Large": ProximityConfig(vertical: 800, horizontalDist: 2000, horizontalTime: 60),
    "X-Large": ProximityConfig(vertical: 1200, horizontalDist: 3000, horizontalTime: 90),
  };
  late ProximityConfig proximityProfile;
  late String proximityProfileName;

  // --- Patreon
  String _patreonName = "";
  String _patreonEmail = "";

  // --- Misc
  bool _autoStartStopFlight = true;
  bool _chatTts = false;
  String _altInstr = "MSL";

  Settings() {
    selectProximityConfig("Medium");
    _loadSettings();
    initMapCache();
  }

  void initMapCache() async {
    FlutterMapTileCaching.initialise(await RootDirectory.normalCache);
    initDemCache();

    for (final mapName in mapTileThumbnails.keys) {
      final StoreDirectory store = FMTC.instance(mapName);
      await store.manage.createAsync();
      await store.metadata.addAsync(key: 'sourceURL', value: getMapTileLayer(mapName).urlTemplate!);
      await store.metadata.addAsync(
        key: 'validDuration',
        value: '14',
      );
      await store.metadata.addAsync(
        key: 'behaviour',
        value: 'cacheFirst',
      );
    }

    // Do a regular purge of old tiles
    purgeMapTileCache();
  }

  String asReadableSize(double value) {
    if (value <= 0) return '0 B';
    final List<String> units = ['B', 'kB', 'MB', 'GB', 'TB'];
    final int digitGroups = (log(value) / log(1024)).round();
    return '${NumberFormat('#,##0.#').format(value / pow(1024, digitGroups))} ${units[digitGroups]}';
  }

  Future<String> getMapTileCacheSize() async {
    // Add together the cache size for all base map layers
    double sum = 0;
    for (final mapName in mapTileThumbnails.keys) {
      final StoreDirectory store = FMTC.instance(mapName);
      sum += (await store.stats.noCache.storeSizeAsync) * 1024;
    }

    // Also add the elevation map
    final StoreDirectory demStore = FMTC.instance("dem");
    sum += (await demStore.stats.noCache.storeSizeAsync) * 1024;

    return asReadableSize(sum);
  }

  void purgeMapTileCache() async {
    final threshhold = DateTime.now().subtract(const Duration(days: 14));
    for (final mapName in mapTileThumbnails.keys) {
      final StoreDirectory store = FMTC.instance(mapName);
      int countDelete = 0;
      int countRemain = 0;
      for (final tile in store.access.tiles.listSync()) {
        if (tile.statSync().changed.isBefore(threshhold)) {
          // debugPrint("Deleting Tile: ${tile.path}");
          tile.deleteSync();
          countDelete++;
        } else {
          countRemain++;
        }
      }
      debugPrint("Scanned $mapName and deleted $countDelete / ${countRemain + countDelete} tiles.");
      store.stats.invalidateCachedStatistics();
    }
  }

  void emptyMapTileCache() {
    // Empty elevation map cache
    final StoreDirectory demStore = FMTC.instance("dem");
    debugPrint("Clear Map Cache: dem");
    demStore.manage.reset();

    // Empty standard map caches
    for (final mapName in mapTileThumbnails.keys) {
      final StoreDirectory store = FMTC.instance(mapName);
      debugPrint("Clear Map Cache: $mapName");
      store.manage.reset();
    }
  }

  _loadSettings() {
    SharedPreferences.getInstance().then((prefs) {
      // --- Units
      _displayUnitsSpeed = DisplayUnitsSpeed.values[prefs.getInt("settings.displayUnitsSpeed") ?? 0];
      _displayUnitsVario = DisplayUnitsVario.values[prefs.getInt("settings.displayUnitsVario") ?? 0];
      _displayUnitsDist = DisplayUnitsDist.values[prefs.getInt("settings.displayUnitsDist") ?? 0];
      _displayUnitsFuel = DisplayUnitsFuel.values[prefs.getInt("settings.displayUnitsFuel") ?? 0];

      configUnits(
          speed: displayUnitsSpeed, vario: _displayUnitsVario, dist: _displayUnitsDist, fuel: _displayUnitsFuel);

      // --- UI
      _showWeatherOverlay = prefs.getBool("settings.showWeatherOverlay") ?? true;
      _showAirspaceOverlay = prefs.getBool("settings.showAirspaceOverlay") ?? true;
      _northlockMap = prefs.getBool("settings.northlockMap") ?? true;
      _northlockWind = prefs.getBool("settings.northlockWind") ?? true;
      _mapControlsRightSide = prefs.getBool("settings.mapControlsRightSide") ?? false;
      _showPilotNames = prefs.getBool("settings.showPilotNames") ?? false;

      _groundMode = prefs.getBool("settings.groundMode") ?? false;
      _groundModeTelemetry = prefs.getBool("settings.groundModeTelemetry") ?? false;

      _curMapTiles = prefs.getString("settings.curMapTiles") ?? mapTileThumbnails.keys.first;
      for (String name in _mapOpacity.keys) {
        _mapOpacity[name] = prefs.getDouble("settings.mapOpacity_$name") ?? 1.0;
      }

      // --- ADSB
      selectProximityConfig(prefs.getString("settings.adsbProximityProfile") ?? "Medium");

      // --- Patreon
      _patreonName = prefs.getString("settings.patreonName") ?? "";
      _patreonEmail = prefs.getString("settings.patreonEmail") ?? "";

      // --- Misc
      _autoStartStopFlight = prefs.getBool("settings.autoStartStopFlight") ?? true;
      _chatTts = prefs.getBool("settings.chatTts") ?? false;
      _altInstr = prefs.getString("settings.altInstr") ?? "MSL";
    });
  }

  // --- UI
  bool get northlockMap => _northlockMap;
  set northlockMap(bool value) {
    _northlockMap = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.northlockMap", _northlockMap);
    });
    notifyListeners();
  }

  bool get northlockWind => _northlockWind;
  set northlockWind(bool value) {
    _northlockWind = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.northlockWind", _northlockWind);
    });
    notifyListeners();
  }

  bool get showWeatherOverlay => _showWeatherOverlay;
  set showWeatherOverlay(bool value) {
    _showWeatherOverlay = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.showWeatherOverlay", _showWeatherOverlay);
    });
    notifyListeners();
  }

  bool get showAirspaceOverlay => _showAirspaceOverlay;
  set showAirspaceOverlay(bool value) {
    _showAirspaceOverlay = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.showAirspaceOverlay", _showAirspaceOverlay);
    });
    notifyListeners();
  }

  // --- mapControlsRightSide
  bool get mapControlsRightSide => _mapControlsRightSide;
  set mapControlsRightSide(bool value) {
    _mapControlsRightSide = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.mapControlsRightSide", _mapControlsRightSide);
    });
    notifyListeners();
  }

  // --- showPilotNames
  bool get showPilotNames => _showPilotNames;
  set showPilotNames(bool value) {
    _showPilotNames = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.showPilotNames", _showPilotNames);
    });
    notifyListeners();
  }

  // --- displayUnits
  DisplayUnitsSpeed get displayUnitsSpeed => _displayUnitsSpeed;
  set displayUnitsSpeed(DisplayUnitsSpeed value) {
    _displayUnitsSpeed = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsSpeed", _displayUnitsSpeed.index);
    });
    configUnits(speed: _displayUnitsSpeed);
    notifyListeners();
  }

  DisplayUnitsVario get displayUnitsVario => _displayUnitsVario;
  set displayUnitsVario(DisplayUnitsVario value) {
    _displayUnitsVario = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsVario", _displayUnitsVario.index);
    });
    configUnits(vario: _displayUnitsVario);
    notifyListeners();
  }

  DisplayUnitsDist get displayUnitsDist => _displayUnitsDist;
  set displayUnitsDist(DisplayUnitsDist value) {
    _displayUnitsDist = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsDist", _displayUnitsDist.index);
    });
    configUnits(dist: _displayUnitsDist);
    notifyListeners();
  }

  DisplayUnitsFuel get displayUnitsFuel => _displayUnitsFuel;
  set displayUnitsFuel(DisplayUnitsFuel value) {
    _displayUnitsFuel = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsFuel", _displayUnitsFuel.index);
    });
    configUnits(fuel: _displayUnitsFuel);
    notifyListeners();
  }

  bool get spoofLocation => _spoofLocation;
  set spoofLocation(bool value) {
    _spoofLocation = value;
    notifyListeners();
  }

  bool get groundMode => _groundMode;
  set groundMode(bool value) {
    _groundMode = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.groundMode", _groundMode);
    });
    notifyListeners();
  }

  bool get groundModeTelemetry => _groundModeTelemetry;
  set groundModeTelemetry(bool value) {
    _groundModeTelemetry = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.groundModeTelemetry", _groundModeTelemetry);
    });
    notifyListeners();
  }

  // --- ADSB
  void selectProximityConfig(String name) {
    proximityProfile = proximityProfileOptions[name] ?? proximityProfileOptions["Medium"]!;
    proximityProfileName = name;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString("settings.adsbProximityProfile", name);
    });
    notifyListeners();
  }

  // --- Patreon
  String get patreonName => _patreonName;
  set patreonName(String value) {
    _patreonName = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString("settings.patreonName", value);
    });
    notifyListeners();
  }

  String get patreonEmail => _patreonEmail;
  set patreonEmail(String value) {
    _patreonEmail = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString("settings.patreonEmail", value);
    });
    notifyListeners();
  }

  String get curMapTiles => _curMapTiles;
  set curMapTiles(String value) {
    _curMapTiles = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString("settings.curMapTiles", value);
    });
    notifyListeners();
  }

  double mapOpacity(String name) => _mapOpacity[name] ?? 1.0;
  void setMapOpacity(String name, double value) {
    _mapOpacity[name] = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble("settings.mapOpacity_$name", value);
    });
    notifyListeners();
  }

  // --- Misc
  bool get autoStartStopFlight => _autoStartStopFlight;
  set autoStartStopFlight(bool value) {
    _autoStartStopFlight = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.autoStartStopFlight", _autoStartStopFlight);
    });
    notifyListeners();
  }

  bool get chatTts => _chatTts;
  set chatTts(bool value) {
    _chatTts = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.chatTts", _chatTts);
    });
    notifyListeners();
  }

  String get altInstr => _altInstr;
  set altInstr(String value) {
    _altInstr = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString("settings.altInstr", value);
    });
    notifyListeners();
  }
}
