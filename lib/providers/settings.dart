import 'package:flutter/material.dart';

class Settings with ChangeNotifier {
  bool _spoofLocation = false;

  bool get spoofLocation => _spoofLocation;
  set spoofLocation(bool value) {
    _spoofLocation = value;
    notifyListeners();
  }
}
