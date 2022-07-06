import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  TileLayerOptions getMapTileLayer(String name) {
    switch (name) {
      case "sectional":
        return TileLayerOptions(
            urlTemplate: 'http://wms.chartbundle.com/tms/v1.0/sec/{z}/{x}/{y}.png?type=google',
            maxNativeZoom: 13,
            minZoom: 4,
            opacity: (_mapOpacity["sectional"] ?? 1.0) * 0.8 + 0.2);
      case "satellite":
        return TileLayerOptions(
            urlTemplate:
                'https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}',
            maxNativeZoom: 20,
            opacity: (_mapOpacity["satellite"] ?? 1.0) * 0.8 + 0.2);
      default:
        return TileLayerOptions(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
        );
    }
  }

  final Map<String, Image> mapTileThumbnails = {
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

  Settings() {
    selectProximityConfig("Medium");
    _loadSettings();
  }

  _loadSettings() {
    SharedPreferences.getInstance().then((prefs) {
      _displayUnitsSpeed = DisplayUnitsSpeed.values[prefs.getInt("settings.displayUnitsSpeed") ?? 0];
      _displayUnitsVario = DisplayUnitsVario.values[prefs.getInt("settings.displayUnitsVario") ?? 0];
      _displayUnitsDist = DisplayUnitsDist.values[prefs.getInt("settings.displayUnitsDist") ?? 0];
      _mapControlsRightSide = prefs.getBool("settings.mapControlsRightSide") ?? false;
      _showPilotNames = prefs.getBool("settings.showPilotNames") ?? false;
      _displayUnitsFuel = DisplayUnitsFuel.values[prefs.getInt("settings.displayUnitsFuel") ?? 0];

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
    notifyListeners();
  }

  DisplayUnitsVario get displayUnitsVario => _displayUnitsVario;
  set displayUnitsVario(DisplayUnitsVario value) {
    _displayUnitsVario = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsVario", _displayUnitsVario.index);
    });
    notifyListeners();
  }

  DisplayUnitsDist get displayUnitsDist => _displayUnitsDist;
  set displayUnitsDist(DisplayUnitsDist value) {
    _displayUnitsDist = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsDist", _displayUnitsDist.index);
    });
    notifyListeners();
  }

  DisplayUnitsFuel get displayUnitsFuel => _displayUnitsFuel;
  set displayUnitsFuel(DisplayUnitsFuel value) {
    _displayUnitsFuel = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsFuel", _displayUnitsFuel.index);
    });
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
}
