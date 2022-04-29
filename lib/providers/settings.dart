import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DisplayUnits {
  english,
  metric1, // kph
  metric2, // m/s
}

class Settings with ChangeNotifier {
  bool _spoofLocation = false;
  bool _showAirspace = false;
  DisplayUnits _displayUnits = DisplayUnits.english;
  bool _mapControlsRightSide = false;

  Settings() {
    _loadSettings();
  }

  _loadSettings() {
    SharedPreferences.getInstance().then((prefs) {
      _displayUnits =
          DisplayUnits.values[prefs.getInt("settings.displayUnits") ?? 0];
      _mapControlsRightSide =
          prefs.getBool("settings.mapControlsRightSide") ?? false;
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
  DisplayUnits get displayUnits => _displayUnits;
  set displayUnits(DisplayUnits value) {
    _displayUnits = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnits", _displayUnits.index);
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
