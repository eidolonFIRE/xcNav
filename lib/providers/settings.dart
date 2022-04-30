import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/units.dart';

class Settings with ChangeNotifier {
  bool _spoofLocation = false;
  bool _showAirspace = false;
  var _displayUnitsSpeed = DisplayUnitsSpeed.mph;
  var _displayUnitsVario = DisplayUnitsVario.fpm;
  var _displayUnitsDist = DisplayUnitsDist.imperial;
  var _displayUnitsFuel = DisplayUnitsFuel.liter;
  bool _mapControlsRightSide = false;

  Settings() {
    _loadSettings();
  }

  _loadSettings() {
    SharedPreferences.getInstance().then((prefs) {
      _displayUnitsSpeed = DisplayUnitsSpeed
          .values[prefs.getInt("settings.displayUnitsSpeed") ?? 0];
      _displayUnitsVario = DisplayUnitsVario
          .values[prefs.getInt("settings.displayUnitsVario") ?? 0];
      _displayUnitsDist = DisplayUnitsDist
          .values[prefs.getInt("settings.displayUnitsDist") ?? 0];
      _mapControlsRightSide =
          prefs.getBool("settings.mapControlsRightSide") ?? false;
      _displayUnitsFuel = DisplayUnitsFuel
          .values[prefs.getInt("settings.displayUnitsFuel") ?? 0];
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
}
