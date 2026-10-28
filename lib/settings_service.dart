import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xcnav/locale.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/flight_detector.dart';
import 'package:xcnav/models/glide_range.dart';

import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';

/// Holds and stores an individual setting.
class SettingConfig<T> {
  final SharedPreferences _prefsInstance;

  /// This id will be used as the save path in `sharedPreferences`
  final String id;
  final String catagory;
  final String title;
  final String? description;
  final Widget? icon;
  final Widget? subtitle;

  /// Shown after the value in the settings editor's text field (e.g. ":1")
  final String? suffix;

  late ValueNotifier<T> _value;
  T defaultValue;

  final T Function(T value)? setter;

  ValueListenable<T> get listenable => _value;

  T get value {
    return _value.value ?? defaultValue;
  }

  void reset() => value = defaultValue;

  set value(T newValue) {
    if (setter != null) {
      // use custom setter
      _value.value = setter!(newValue);
    } else {
      _value.value = newValue;
    }
    if (id == "") return;
    if (value is Enum) {
      // Handle enum type
      _prefsInstance.setInt("settings.$id", (value as Enum).index);
      debugPrint("Set enum type ${(value as Enum).index}");
    } else {
      switch (T.toString()) {
        case "List<String>":
          _prefsInstance.setStringList("settings.$id", newValue as List<String>);
          break;
        case "String":
          _prefsInstance.setString("settings.$id", newValue as String);
          break;
        case "bool":
          _prefsInstance.setBool("settings.$id", newValue as bool);
          break;
        case "double":
          _prefsInstance.setDouble("settings.$id", newValue as double);
          break;
        case "int":
          _prefsInstance.setInt("settings.$id", newValue as int);
          break;
      }
    }
  }

  SettingConfig(SettingsMgr mgr, this._prefsInstance, this.catagory, this.id, this.defaultValue,
      {required this.title,
      this.description,
      this.icon,
      bool hidden = false,
      this.subtitle,
      this.suffix,
      this.setter}) {
    if (id.startsWith("settings.")) {
      throw "Setting ID automatically starts with \"settings.\"";
    }

    if (id == "") {
      _value = ValueNotifier<T>(defaultValue);
    } else {
      if (defaultValue is Enum) {
        // Handle enum type
        int? loadedInt = _prefsInstance.getInt("settings.$id");
        if (loadedInt == null) {
          _value = ValueNotifier<T>(defaultValue);
        } else {
          switch (T.toString()) {
            // NOTE: Need to add each supported enum here
            case "DisplayUnitsDist":
              _value = ValueNotifier<T>(DisplayUnitsDist.values[loadedInt] as T);
              break;
            case "DisplayUnitsSpeed":
              _value = ValueNotifier<T>(DisplayUnitsSpeed.values[loadedInt] as T);
              break;
            case "DisplayUnitsVario":
              _value = ValueNotifier<T>(DisplayUnitsVario.values[loadedInt] as T);
              break;
            case "DisplayUnitsFuel":
              _value = ValueNotifier<T>(DisplayUnitsFuel.values[loadedInt] as T);
              break;
            case "AltimeterMode":
              _value = ValueNotifier<T>(AltimeterMode.values[loadedInt] as T);
              break;
            case "ProximitySize":
              _value = ValueNotifier<T>(ProximitySize.values[loadedInt] as T);
              break;
            case "MapTileSrc":
              _value = ValueNotifier<T>(MapTileSrc.values[loadedInt] as T);
              break;
            case "LanguageOverride":
              _value = ValueNotifier<T>(LanguageOverride.values[loadedInt] as T);
              break;
            case "GlideRangeMode":
              _value = ValueNotifier<T>(GlideRangeMode.values[loadedInt] as T);
              break;
            default:
              throw "Unrecognized enum class ${T.toString()}";
          }
        }
      } else {
        switch (T.toString()) {
          case "List<String>":
            _value =
                ValueNotifier<T>((_prefsInstance.getStringList("settings.$id") ?? defaultValue as List<String>) as T);
            break;
          case "String":
            _value = ValueNotifier<T>((_prefsInstance.getString("settings.$id") ?? defaultValue as String) as T);
            break;
          case "bool":
            _value = ValueNotifier<T>((_prefsInstance.getBool("settings.$id") ?? defaultValue as bool) as T);
            break;
          case "double":
            _value = ValueNotifier<T>((_prefsInstance.getDouble("settings.$id") ?? defaultValue as double) as T);
            break;
          case "int":
            _value = ValueNotifier<T>((_prefsInstance.getInt("settings.$id") ?? defaultValue as int) as T);
            break;
          default:
            throw "Unsupported Settings Type($T) !";
        }
      }
    }

    // Register with manager
    if (!hidden) {
      mgr.settings.putIfAbsent(catagory, () => []);
      mgr.settings[catagory]!.add(SettingMgrItem(config: this));
      if (mgr.ids.contains(id)) {
        throw "Settings Manager already has id $id !";
      } else {
        mgr.ids.add(id);
      }
    }
  }
}

class SettingAction {
  final String catagory;
  String title;
  String? description;
  final Icon? actionIcon;

  Function() callback;

  SettingAction(SettingsMgr mgr, this.catagory, this.callback,
      {required this.title, this.description, this.actionIcon}) {
    // Register with manager
    mgr.settings.putIfAbsent(catagory, () => []);
    mgr.settings[catagory]!.add(SettingMgrItem(action: this));
  }
}

class SettingMgrItem {
  final SettingConfig? config;
  final SettingAction? action;

  bool get isConfig => config != null;
  bool get isAction => action != null;

  // --- pass-through fields
  String get catagory => config?.catagory ?? action?.catagory ?? "";
  String get title => config?.title ?? action?.title ?? "";
  String? get description => config?.description ?? action?.description;

  SettingMgrItem({this.config, this.action}) {
    if (config != null && action != null) {
      throw "Cannot set both config and action in SettingMgrItem";
    }
    if (config == null && action == null) {
      throw "Must set either config or action in SettingMgrItem";
    }
  }
}

/// Manages global instances of `Setting`s
class SettingsMgr {
  /// Flat look-up list of settings
  Set ids = {};
  late final SharedPreferences prefsInstance;

  /// Look-up list of settings by catagory
  Map<String, List<SettingMgrItem>> settings = {};

  // --- General
  late final SettingConfig<LanguageOverride> languageOverride;
  late final SettingConfig<bool> groundMode;
  late final SettingConfig<bool> autoRecordFlight;

  // --- Glide Range
  late final SettingConfig<GlideRangeMode> glideRangeMode;
  late final SettingConfig<double> glideRangeDefaultRatio;
  late final SettingConfig<double> glideRangeMargin;

  // --- UI
  late final SettingConfig<AltimeterMode> primaryAltimeter;
  late final SettingConfig<double> altimeterVsiThresh;
  late final SettingConfig<bool> mapControlsRightSide;
  late final SettingConfig<bool> showPilotNames;
  late final SettingConfig<bool> hideWeatherObservations;
  // late final SettingConfig<bool> showWeatherOverlay;
  late final SettingConfig<bool> showAirspaceOverlay;
  late final SettingConfig<bool> showAirports;
  late final SettingConfig<bool> groupViewWaypoint;

  // --- Display Units
  late final SettingConfig<DisplayUnitsDist> displayUnitDist;
  late final SettingConfig<DisplayUnitsSpeed> displayUnitSpeed;
  late final SettingConfig<DisplayUnitsVario> displayUnitVario;
  late final SettingConfig<DisplayUnitsFuel> displayUnitFuel;

  // --- Misc
  late final SettingConfig<ProximitySize> adsbProximitySize;
  late final SettingConfig<List<String>> adsbFilters;
  late final SettingAction adsbTestAudio;
  late final SettingConfig<bool> pauseMusicForSpeech;
  late final SettingConfig<bool> rumOptOut;

  // --- Experimental
  late final SettingConfig<bool> showServoCarbMenu;
  late final SettingConfig<bool> forceGpsAltitude;
  late final SettingConfig<int> gpsUpdateInterval;
  late final SettingAction flightDetection;
  late final SettingConfig<double> launchMinSpeed;
  late final SettingConfig<double> launchMaxSpeed;
  late final SettingConfig<bool> launchUseAgl;
  late final SettingConfig<double> launchMinAgl;
  late final SettingConfig<bool> launchUseVario;
  late final SettingConfig<double> launchMinVario;
  late final SettingConfig<int> launchHoldTime;
  late final SettingConfig<bool> launchUseSp140Armed;
  late final SettingConfig<double> landingMaxSpeed;
  late final SettingConfig<bool> landingUseVario;
  late final SettingConfig<double> landingMaxVario;
  late final SettingConfig<bool> landingUseAgl;
  late final SettingConfig<double> landingMaxAgl;
  late final SettingConfig<int> landingHoldTime;
  late final SettingConfig<bool> landingUseSp140Armed;

  // --- Debug Tools
  late final SettingConfig<bool> spoofLocation;
  late final SettingAction clearMapCache;
  late final SettingAction clearAvatarCache;
  late final SettingAction eraseIdentity;

  // --- Hidden
  late final SettingConfig<bool> chatTTS;
  late final SettingConfig<bool> groundModeTelem;
  late final SettingConfig<bool> northlockMap;
  late final SettingConfig<bool> northlockWind;
  late final SettingConfig<MapTileSrc> mainMapTileSrc;
  late final SettingConfig<double> mainMapOpacity;
  late final SettingConfig<String> datadogSdkId;
  late final SettingConfig<AltimeterMode> audioCueAltimeter;
  late final SettingConfig<List<String>> bleAutoDevices;

  // --- Meshtastic (edited in meshtastic dialog)
  late final SettingConfig<bool> clientUseCellular;
  late final SettingConfig<bool> clientUseMesh;
  late final SettingConfig<int> meshtasticPreset;

  late final SettingConfig<int> sp140FuelSaveIntervalMin;
  late final SettingConfig<bool> sp140AudioWarnings;
  late final SettingConfig<bool> sp140AudioCritical;

  SettingsMgr(SharedPreferences prefs) {
    // --- General
    languageOverride = SettingConfig(
      this,
      prefs,
      "General",
      "languageOverride",
      LanguageOverride.none,
      title: "Language Override",
      icon: const Icon(Icons.translate),
      subtitle: Text("Requires Restarting xcNav"),
    );
    groundMode = SettingConfig(this, prefs, "General", "groundMode", false,
        title: "ground_support_mode",
        icon: const Icon(Icons.directions_car),
        description: "Alters UI and doesn't record track.");

    autoRecordFlight = SettingConfig(this, prefs, "General", "autoRecordFlight", true,
        title: "auto_record_flight",
        icon: const Icon(Icons.play_arrow),
        description: "Flight recorder automatically starts and stops.");

    // --- Glide Range
    glideRangeMode = SettingConfig(this, prefs, "Glide Range", "glideRangeMode", GlideRangeMode.auto,
        title: "Glide range mode", hidden: true);
    glideRangeDefaultRatio = SettingConfig(this, prefs, "Glide Range", "glideRangeDefaultRatio", 5.0,
        title: "glide_range_default_ratio",
        icon: const Icon(Icons.paragliding),
        description: "Glide ratio the map's glide range uses in \"Always\" mode when not on a 1:1 to 12:1 glide.",
        suffix: ": 1 ",
        setter: (value) => value.clamp(1.0, maxGlideRatio));
    glideRangeMargin = SettingConfig(this, prefs, "Glide Range", "glideRangeMargin", 50.0,
        title: "glide_range_margin",
        icon: const Icon(Icons.height),
        description: "Height to keep in reserve. The glide range ends where you'd be this high above the ground.",
        setter: (value) => value.clamp(0.0, 1000.0));

    // --- UI
    primaryAltimeter = SettingConfig(this, prefs, "UI", "primaryAltimeter", AltimeterMode.msl,
        title: "primary_altimeter",
        icon: const Icon(Icons.vertical_align_top),
        description: "Which altimeter is on top.");
    altimeterVsiThresh = SettingConfig(this, prefs, "UI", "altimeterVsiThresh", 0.15,
        title: "altimeter_vsi_thresh",
        icon: SvgPicture.asset(
          "assets/images/arrow.svg",
          height: 20,
        ),
        description: "The \"deadzone\" for the up/down arrow next to altimeter.");
    mapControlsRightSide = SettingConfig(this, prefs, "UI", "mapControlsRightSide", false,
        title: "right_hand_ui",
        description: "Move map control buttons to the right side.",
        icon: const Icon(Icons.swap_horiz));
    showPilotNames = SettingConfig(this, prefs, "UI", "showPilotNames", false,
        title: "always_show_pilot_names", description: "", icon: const Icon(Icons.abc));
    hideWeatherObservations = SettingConfig(this, prefs, "UI", "hideWeatherObservations", false,
        title: "hide_wind_observations",
        description: "Hide wind observations from weather stations on map.",
        icon: const Icon(Icons.air));

    // showWeatherOverlay = SettingConfig(this, prefs, "UI", "showWeatherOverlay", false,
    //     title: "Show weather overlay", description: "", icon: const Icon(Icons.cloud));
    showAirspaceOverlay =
        SettingConfig(this, prefs, "UI", "showAirspaceOverlay", true, title: "Show airspace overlay", hidden: true);
    showAirports = SettingConfig(this, prefs, "UI", "showAirports", true, title: "Show airports", hidden: true);
    groupViewWaypoint = SettingConfig(this, prefs, "UI", "groupViewWaypoint", false,
        title: "group_view_includes_waypoints", icon: const Icon(Icons.pin_drop));

    // --- Display Units
    displayUnitDist = SettingConfig(this, prefs, "Display Units", "displayUnitDist", DisplayUnitsDist.imperial,
        title: "Distance", icon: const Icon(Icons.architecture));
    displayUnitSpeed = SettingConfig(this, prefs, "Display Units", "displayUnitSpeed", DisplayUnitsSpeed.mph,
        title: "Speed", icon: const Icon(Icons.timer));
    displayUnitVario = SettingConfig(this, prefs, "Display Units", "displayUnitVario", DisplayUnitsVario.fpm,
        title: "Vario", icon: const Icon(Icons.trending_up));
    displayUnitFuel = SettingConfig(this, prefs, "Display Units", "displayUnitFuel", DisplayUnitsFuel.liter,
        title: "Fuel", icon: const Icon(Icons.local_gas_station));

    displayUnitDist.listenable.addListener(() {
      configUnits(dist: displayUnitDist.value);
    });
    displayUnitSpeed.listenable.addListener(() {
      configUnits(speed: displayUnitSpeed.value);
    });
    displayUnitVario.listenable.addListener(() {
      configUnits(vario: displayUnitVario.value);
    });
    displayUnitFuel.listenable.addListener(() {
      configUnits(fuel: displayUnitFuel.value);
    });

    configUnits(
        speed: displayUnitSpeed.value,
        vario: displayUnitVario.value,
        dist: displayUnitDist.value,
        fuel: displayUnitFuel.value);

    // --- Misc
    adsbProximitySize = SettingConfig(this, prefs, "Misc", "adsbProximitySize", ProximitySize.medium,
        title: "adsb_proximity_profile", icon: const Icon(Icons.radar));
    adsbFilters = SettingConfig(this, prefs, "Misc", "adsbFilters", [],
        title: "filter_tail_numbers",
        icon: const Icon(Icons.filter_alt),
        setter: (value) => value.map((e) => e.toUpperCase()).toList());
    adsbTestAudio =
        SettingAction(this, "Misc", () => null, title: "test_audio_cues", actionIcon: const Icon(Icons.volume_up));
    pauseMusicForSpeech = SettingConfig(this, prefs, "Misc", "pauseMusicForSpeech", false,
        title: "pause_music_for_speech",
        icon: const Icon(Icons.music_off),
        description: "Pause music while audio cues play, instead of lowering it.",
        hidden: true);
    rumOptOut = SettingConfig(this, prefs, "Misc", "rumOptOut", false,
        title: "opt_out_usage_stats",
        icon: const Icon(Icons.cancel),
        subtitle: Text.rich(TextSpan(children: [
          const WidgetSpan(
              child: Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.help, size: 16, color: Colors.lightBlue),
          )),
          TextSpan(text: "View list of metrics captured.  "),
          TextSpan(
              text: "External Link",
              style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  launchUrl(Uri.parse("https://github.com/eidolonFIRE/xcNav/blob/main/usage_stats.md"));
                })
        ])));

    // --- Experimental
    showServoCarbMenu = SettingConfig(this, prefs, "Experimental", "showServoCarbMenu", false,
        title: "show_servocarb", icon: const Icon(Icons.settings_applications_sharp), hidden: true);
    forceGpsAltitude = SettingConfig(this, prefs, "Experimental", "forceGpsAltitude", false,
        title: "force_gps_altitude",
        icon: const Icon(Icons.satellite_alt),
        description: "Ignore barometric pressure and use GPS MSL altitude for all calculations.");
    gpsUpdateInterval = SettingConfig(this, prefs, "Experimental", "gpsUpdateInterval", 3000,
        title: "gps_update_interval",
        icon: const Icon(Icons.speed),
        description: "GPS update interval in milliseconds (Android only). Lower values use more battery.",
        setter: (value) => value < 500 ? 500 : value,
        hidden: defaultTargetPlatform != TargetPlatform.android);

    flightDetection = SettingAction(this, "Experimental", () => null,
        title: "flight_detection", actionIcon: const Icon(Icons.flight_takeoff));

    // --- Launch / Landing detection (edited in flight detection dialog)
    const launchDefaults = LaunchDetectorConfig();
    launchMinSpeed = SettingConfig(this, prefs, "Flight Detection", "launchMinSpeed", launchDefaults.minSpeed,
        title: "Launch Min Speed", hidden: true, setter: (value) => value < 0 ? 0.0 : value);
    launchMaxSpeed = SettingConfig(this, prefs, "Flight Detection", "launchMaxSpeed", launchDefaults.maxSpeed,
        title: "Launch Max Speed", hidden: true, setter: (value) => value < 0 ? 0.0 : value);
    launchUseAgl = SettingConfig(this, prefs, "Flight Detection", "launchUseAgl", launchDefaults.useAgl,
        title: "Launch Use AGL", hidden: true);
    launchMinAgl = SettingConfig(this, prefs, "Flight Detection", "launchMinAgl", launchDefaults.minAgl,
        title: "Launch Min AGL", hidden: true, setter: (value) => value < 0 ? 0.0 : value);
    launchUseVario = SettingConfig(this, prefs, "Flight Detection", "launchUseVario", launchDefaults.useVario,
        title: "Launch Use Vario", hidden: true);
    launchMinVario = SettingConfig(this, prefs, "Flight Detection", "launchMinVario", launchDefaults.minVario,
        title: "Launch Min Vario", hidden: true, setter: (value) => value < 0 ? 0.0 : value);
    launchHoldTime = SettingConfig(this, prefs, "Flight Detection", "launchHoldTime", launchDefaults.holdTime.inSeconds,
        title: "Launch Hold Time", hidden: true, setter: (value) => value < 1 ? 1 : value);
    launchUseSp140Armed = SettingConfig(
        this, prefs, "Flight Detection", "launchUseSp140Armed", launchDefaults.useSp140Armed,
        title: "Launch Use SP140 Armed", hidden: true);

    const landingDefaults = LandingDetectorConfig();
    landingMaxSpeed = SettingConfig(this, prefs, "Flight Detection", "landingMaxSpeed", landingDefaults.maxSpeed,
        title: "Landing Max Speed", hidden: true, setter: (value) => value < 0 ? 0.0 : value);
    landingUseVario = SettingConfig(this, prefs, "Flight Detection", "landingUseVario", landingDefaults.useVario,
        title: "Landing Use Vario", hidden: true);
    landingMaxVario = SettingConfig(this, prefs, "Flight Detection", "landingMaxVario", landingDefaults.maxVario,
        title: "Landing Max Vario", hidden: true, setter: (value) => value < 0 ? 0.0 : value);
    landingUseAgl = SettingConfig(this, prefs, "Flight Detection", "landingUseAgl", landingDefaults.useAgl,
        title: "Landing Use AGL", hidden: true);
    landingMaxAgl = SettingConfig(this, prefs, "Flight Detection", "landingMaxAgl", landingDefaults.maxAgl,
        title: "Landing Max AGL", hidden: true, setter: (value) => value < 0 ? 0.0 : value);
    landingHoldTime = SettingConfig(
        this, prefs, "Flight Detection", "landingHoldTime", landingDefaults.holdTime.inSeconds,
        title: "Landing Hold Time", hidden: true, setter: (value) => value < 1 ? 1 : value);
    landingUseSp140Armed = SettingConfig(
        this, prefs, "Flight Detection", "landingUseSp140Armed", landingDefaults.useSp140Armed,
        title: "Landing Use SP140 Armed", hidden: true);

    // --- Debug Tools
    spoofLocation = SettingConfig(this, prefs, "Debug Tools", "", false,
        title: "spoof_location",
        icon: const Icon(
          Icons.location_off,
        ),
        description: "Useful for test driving while on the ground.");
    clearMapCache = SettingAction(this, "Debug Tools", () => null,
        title: "clear_map_cache",
        actionIcon: const Icon(
          Icons.map,
        ));
    clearAvatarCache = SettingAction(this, "Debug Tools", () => null,
        title: "clear_avatar_cache",
        actionIcon: const Icon(
          Icons.account_circle,
        ));
    eraseIdentity = SettingAction(this, "Debug Tools", () => null,
        title: "erase_identity",
        actionIcon: const Icon(
          Icons.badge,
        ));

    // --- Hidden
    chatTTS = SettingConfig(this, prefs, "UI", "chatTTS", false,
        title: "Chat text-to-speech", icon: const Icon(Icons.volume_up), hidden: true);
    groundModeTelem = SettingConfig(this, prefs, "General", "groundModeTelem", false,
        title: "Ground Mode Telemetry",
        icon: const Icon(Icons.minor_crash),
        description: "Transmit telemetry while in ground support mode.",
        hidden: true);
    northlockMap = SettingConfig(this, prefs, "UI", "northlockMap", true, title: "Lock map to North-Up", hidden: true);
    northlockWind =
        SettingConfig(this, prefs, "UI", "northlockWind", false, title: "Lock wind detector to North-Up", hidden: true);
    mainMapTileSrc =
        SettingConfig(this, prefs, "UI", "mainMapTileSrc", MapTileSrc.topo, title: "Map Tile Sourc", hidden: true);
    mainMapOpacity = SettingConfig(this, prefs, "UI", "mainMapOpacity", 1.0, title: "Main Map Opacity", hidden: true);
    datadogSdkId = SettingConfig(this, prefs, "Debug", "datadogSdkId", "", title: "DatadogSdk user ID", hidden: true);

    audioCueAltimeter = SettingConfig(this, prefs, "Audio Cues", "audioCueAltimeter", AltimeterMode.msl,
        title: "Altimeter Mode", icon: const Icon(Icons.vertical_align_top), hidden: true);

    bleAutoDevices =
        SettingConfig(this, prefs, "ble", "bleAutoConnectDevices", [], title: "Auto Connect Devices", hidden: true);

    clientUseCellular =
        SettingConfig(this, prefs, "meshtastic", "clientUseCellular", true, title: "Group over cellular", hidden: true);
    clientUseMesh =
        SettingConfig(this, prefs, "meshtastic", "clientUseMesh", true, title: "Group over Meshtastic", hidden: true);
    // `Config.LoRaConfig.ModemPreset` value (default LONG_FAST)
    meshtasticPreset =
        SettingConfig(this, prefs, "meshtastic", "meshtasticPreset", 0, title: "Meshtastic preset", hidden: true);

    sp140FuelSaveIntervalMin = SettingConfig(this, prefs, "sp140", "sp140FuelSaveIntervalMin", 5,
        title: "SP140 Fuel Save Interval (minutes)", icon: const Icon(Icons.timer), hidden: true);
    sp140AudioWarnings = SettingConfig(this, prefs, "sp140", "sp140AudioWarnings", true,
        title: "SP140 Warning Alert Audio", icon: const Icon(Icons.warning), hidden: true);
    sp140AudioCritical = SettingConfig(this, prefs, "sp140", "sp140AudioCritical", true,
        title: "SP140 Critical Alert Audio", icon: const Icon(Icons.error), hidden: true);
  }

  LaunchDetectorConfig get launchDetectorConfig => LaunchDetectorConfig(
        minSpeed: launchMinSpeed.value,
        maxSpeed: launchMaxSpeed.value,
        useAgl: launchUseAgl.value,
        minAgl: launchMinAgl.value,
        useVario: launchUseVario.value,
        minVario: launchMinVario.value,
        holdTime: Duration(seconds: launchHoldTime.value),
        useSp140Armed: launchUseSp140Armed.value,
      );

  LandingDetectorConfig get landingDetectorConfig => LandingDetectorConfig(
        maxSpeed: landingMaxSpeed.value,
        useVario: landingUseVario.value,
        maxVario: landingMaxVario.value,
        useAgl: landingUseAgl.value,
        maxAgl: landingMaxAgl.value,
        holdTime: Duration(seconds: landingHoldTime.value),
        useSp140Armed: landingUseSp140Armed.value,
      );

  /// Restore all launch / landing detection settings to defaults.
  void resetFlightDetection() {
    for (final setting in <SettingConfig>[
      launchMinSpeed,
      launchMaxSpeed,
      launchUseAgl,
      launchMinAgl,
      launchUseVario,
      launchMinVario,
      launchHoldTime,
      launchUseSp140Armed,
      landingMaxSpeed,
      landingUseVario,
      landingMaxVario,
      landingUseAgl,
      landingMaxAgl,
      landingHoldTime,
      landingUseSp140Armed,
    ]) {
      setting.reset();
    }
  }
}

/// Singleton
late final SettingsMgr settingsMgr;
