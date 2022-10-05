import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/units.dart';

class Settings with ChangeNotifier {
  // --- Modes
  bool _groundMode = false;
  bool _groundModeTelemetry = false;

  // --- Debug Tools
  bool _spoofLocation = false;

  // --- Map TileProviders
  String _curMapTiles = "topo";
  final Map<String, double> _mapOpacity = {
    "topo": 1.0,
    "sectional": 1.0,
    "satellite": 1.0,
  };
  TileLayerOptions getMapTileLayer(String name, {double? opacity}) {
    TileProvider makeTileProvider(name) {
      return FMTC.instance(name).getTileProvider(
            FMTCTileProviderSettings(
              behavior: CacheBehavior.cacheFirst,
              cachedValidDuration: const Duration(days: 14),
            ),
          );
    }

    switch (name) {
      case "sectional":
        return TileLayerOptions(
            urlTemplate: 'http://wms.chartbundle.com/tms/v1.0/sec/{z}/{x}/{y}.png?type=google',
            tileProvider: makeTileProvider(name),
            maxNativeZoom: 13,
            minZoom: 4,
            opacity: (opacity ?? _mapOpacity["sectional"] ?? 1.0) * 0.8 + 0.2);
      case "satellite":
        return TileLayerOptions(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            tileProvider: makeTileProvider(name),
            maxNativeZoom: 20,
            opacity: (opacity ?? _mapOpacity["satellite"] ?? 1.0) * 0.8 + 0.2);
      default:
        return TileLayerOptions(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
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
  };

  // --- UI
  bool _showAirspace = false;
  bool _mapControlsRightSide = false;
  bool _showPilotNames = false;

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
  bool _chatTts = false;

  Settings() {
    selectProximityConfig("Medium");
    _loadSettings();
    initMapCache();
  }

  void initMapCache() async {
    FlutterMapTileCaching.initialise(await RootDirectory.normalCache);

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
    double sum = 0;
    for (final mapName in mapTileThumbnails.keys) {
      final StoreDirectory store = FMTC.instance(mapName);
      sum += (await store.stats.noCache.storeSizeAsync) * 1024;
    }
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
    for (final mapName in mapTileThumbnails.keys) {
      final StoreDirectory store = FMTC.instance(mapName);
      debugPrint("Clear Map Cache: $mapName");
      store.manage.reset();
    }
  }

  _loadSettings() {
    SharedPreferences.getInstance().then((prefs) {
      _displayUnitsSpeed = DisplayUnitsSpeed.values[prefs.getInt("settings.displayUnitsSpeed") ?? 0];
      _displayUnitsVario = DisplayUnitsVario.values[prefs.getInt("settings.displayUnitsVario") ?? 0];
      _displayUnitsDist = DisplayUnitsDist.values[prefs.getInt("settings.displayUnitsDist") ?? 0];
      _displayUnitsFuel = DisplayUnitsFuel.values[prefs.getInt("settings.displayUnitsFuel") ?? 0];

      configUnits(
          speed: displayUnitsSpeed, vario: _displayUnitsVario, dist: _displayUnitsDist, fuel: _displayUnitsFuel);

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
      _chatTts = prefs.getBool("settings.chatTts") ?? false;
    });
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

  bool get showAirspace => _showAirspace;
  set showAirspace(bool value) {
    _showAirspace = value;
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
  bool get chatTts => _chatTts;
  set chatTts(bool value) {
    _chatTts = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.chatTts", _chatTts);
    });
    notifyListeners();
  }
}
