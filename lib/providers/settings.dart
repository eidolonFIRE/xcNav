import 'package:flutter/material.dart';

class Settings with ChangeNotifier {
  bool _spoofLocation = false;
  bool _showAirspace = false;

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
