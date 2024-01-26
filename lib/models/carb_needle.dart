import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/util.dart';

class CarbNeedleConfig {
  final SharedPreferences prefs;
  final String name;

  /// Field of view in Radians
  double get fov => _fov;
  late final double _fov;
  set fov(value) {
    _fov = value;
    save();
  }

  /// PWM settings

  int get pwmStart => _pwmStart;
  late final int _pwmStart;
  set pwmStart(value) {
    _pwmStart = value;
    save();
  }

  /// PWM settings
  late final int _pwmEnd;
  int get pwmEnd => _pwmEnd;
  set pwmEnd(value) {
    _pwmEnd = value;
    save();
  }

  late final Map<String, double> _presets;
  Map<String, double> get presets => _presets;
  void setPreset(String name, double? value) {
    if (value != null) {
      // Update preset
      _presets[name] = value;
    } else {
      // Remove preset
      _presets.remove(name);
    }
    save();
  }

  String toJson() {
    return jsonEncode({"fov": fov, "pwmStart": pwmStart, "pwmEnd": pwmEnd, "presets": presets});
  }

  String _key() {
    return "carbneedleconfig-$name";
  }

  Future save() async {
    prefs.setString(_key(), toJson());
  }

  CarbNeedleConfig(this.name, this.prefs) {
    // load
    final data = jsonDecode(prefs.getString(_key()) ?? "{}");
    _fov = parseAsDouble(data["fov"]) ?? 160 / 180 * pi;
    _pwmStart = data["pwmStart"] ?? 104;
    _pwmEnd = data["pwmEnd"] ?? 494;
    final Map<String, dynamic> unparsedPresets = (data["presets"] ?? {"Factory": 0.2, "Cruise": 0.5, "Eco": 0.8});
    _presets = unparsedPresets.map((key, value) => MapEntry(key, parseAsDouble(value) ?? 0));
  }
}

class CarbNeedle with ChangeNotifier {
  bool pointerDown = false;

  // TX control
  int _lastTxSent = 0;
  Timer? checkDropped;

  /// Current Needle Setting 0-1
  ///
  /// 0.0 = rich,
  /// 1.0 = lean
  double get mixture => _mixture;
  set mixture(double value) {
    _mixture = max(0, min(1, value));
    _servoPWM = round(config.pwmStart * (1.0 - _mixture) + config.pwmEnd * _mixture).toInt();
    // debugPrint("servo pwm: $_servoPWM");
    tx();
    notifyListeners();
  }

  double _mixture = 0;

  /// Current PWM setting (configured by endstops)
  int get servoPWM => _servoPWM;
  int _servoPWM = 0;

  /// Configuration
  late final CarbNeedleConfig config;

  /// Connection to BLE device
  BluetoothCharacteristic? _bleWriter;

  void loadPreset(String name) {
    mixture = config.presets[name] ?? mixture;
  }

  Future<void> connect(BluetoothCharacteristic writer) async {
    _bleWriter = writer;
    final values = await writer.read();
    debugPrint("$values");
    final pwm = values[0] | (values[1] << 8);
    // inverse interp
    mixture = (pwm - config.pwmStart).toDouble() / (config.pwmEnd - config.pwmStart);
    debugPrint("CarbNeedle connected: ${writer.uuid}, initial: $mixture");
  }

  Future<void> tx() async {
    if (!(_bleWriter?.device.isConnected ?? false)) {
      _bleWriter = null;
      return;
    }
    if (_lastTxSent < clock.now().millisecondsSinceEpoch - 100) {
      // haven't sent a message recently
      _lastTxSent = clock.now().millisecondsSinceEpoch;
      return _bleWriter?.write([servoPWM & 0xff, (servoPWM >> 8) & 0xff]);
    } else {
      // Cancel if already scheduled
      checkDropped?.cancel();
      // Schedule a check afterward
      checkDropped = Timer(const Duration(milliseconds: 100), () {
        _bleWriter?.write([servoPWM & 0xff, (servoPWM >> 8) & 0xff]);
        _lastTxSent = clock.now().millisecondsSinceEpoch;
      });
      return;
    }
  }

  CarbNeedle(String name, SharedPreferences prefs) {
    config = CarbNeedleConfig(name, prefs);
  }
}
