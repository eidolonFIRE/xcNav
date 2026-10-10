import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';

void showFlightDetectionDialog(BuildContext context) {
  showDialog(context: context, builder: (context) => const FlightDetectionDialog());
}

/// Edit the thresholds used to automatically start / stop flight recording.
class FlightDetectionDialog extends StatefulWidget {
  const FlightDetectionDialog({super.key});

  @override
  State<FlightDetectionDialog> createState() => _FlightDetectionDialogState();
}

class _FlightDetectionDialogState extends State<FlightDetectionDialog> {
  /// Round a value (in display units) to a step that makes sense for its range.
  static double _snap(double value, double displayMax) {
    if (displayMax >= 500) return (value / 10).roundToDouble() * 10;
    if (displayMax >= 50) return value.roundToDouble();
    return (value * 10).roundToDouble() / 10;
  }

  static String _fmt(UnitType type, double value) {
    final display = unitConverters[type]!(value);
    return "${printDoubleSimple(display, decimals: 1)} ${getUnitStr(type)}";
  }

  static String _fmtSeconds(int seconds) => "$seconds ${"time.second.short".plural(seconds)}";

  Widget _header(IconData icon, String title, String help) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: Colors.amber),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
          ]),
          const SizedBox(height: 4),
          Text(help, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _labelRow(String label, String value, {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: enabled ? null : Colors.grey))),
        Text(value,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: enabled ? Colors.white : Colors.grey)),
      ]),
    );
  }

  /// Slider for a value stored in SI units, but shown in the user's display units.
  Widget _unitSlider(SettingConfig<double> setting, UnitType type,
      {required String label, required double max, bool enabled = true}) {
    final scale = unitConverters[type]!(1);
    final displayMax = max * scale;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _labelRow(label, _fmt(type, setting.value), enabled: enabled),
      Slider(
          value: (setting.value * scale).clamp(0, displayMax),
          max: displayMax,
          onChanged: enabled
              ? (value) => setState(() => setting.value = _snap(value, displayMax) / scale)
              : null),
    ]);
  }

  Widget _secondsSlider(SettingConfig<int> setting, {required String label, required int max}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _labelRow(label, _fmtSeconds(setting.value)),
      Slider(
          value: setting.value.clamp(1, max).toDouble(),
          min: 1,
          max: max.toDouble(),
          divisions: max - 1,
          onChanged: (value) => setState(() => setting.value = value.round())),
    ]);
  }

  Widget _toggle(SettingConfig<bool> setting, {required String title, String? subtitle}) {
    return SwitchListTile.adaptive(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: setting.value,
        onChanged: (value) => setState(() => setting.value = value));
  }

  Widget _speedRange() {
    const maxSpeed = 40.0;
    final scale = unitConverters[UnitType.speed]!(1);
    final displayMax = maxSpeed * scale;
    final lower = (settingsMgr.launchMinSpeed.value * scale).clamp(0.0, displayMax);
    final upper = (settingsMgr.launchMaxSpeed.value * scale).clamp(lower, displayMax);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _labelRow("flight_detection.speed_between".tr(),
          "${printDoubleSimple(lower, decimals: 1)} - ${_fmt(UnitType.speed, upper / scale)}"),
      RangeSlider(
          values: RangeValues(lower, upper),
          max: displayMax,
          onChanged: (values) => setState(() {
                settingsMgr.launchMinSpeed.value = _snap(values.start, displayMax) / scale;
                settingsMgr.launchMaxSpeed.value = _snap(values.end, displayMax) / scale;
              })),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final launchUseAgl = settingsMgr.launchUseAgl.value;
    final launchUseVario = settingsMgr.launchUseVario.value;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text("settings.title.flight_detection".tr(), style: Theme.of(context).textTheme.headlineSmall),
          ),
          if (!settingsMgr.autoRecordFlight.value)
            Card(
              color: Colors.amber.withAlpha(40),
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.amber),
                title: Text("flight_detection.auto_record_off".tr(), style: const TextStyle(fontSize: 14)),
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Takeoff
                  _header(Icons.flight_takeoff, "flight_detection.takeoff".tr(), "flight_detection.takeoff_help".tr()),
                  _speedRange(),
                  _toggle(settingsMgr.launchUseAgl,
                      title: "flight_detection.above_ground".tr(),
                      subtitle: "flight_detection.above_ground_help".tr()),
                  _unitSlider(settingsMgr.launchMinAgl, UnitType.distFine,
                      label: "flight_detection.higher_than".tr(), max: 150, enabled: launchUseAgl),
                  _toggle(settingsMgr.launchUseVario,
                      title: "flight_detection.climbing".tr(), subtitle: "flight_detection.climbing_help".tr()),
                  _unitSlider(settingsMgr.launchMinVario, UnitType.vario,
                      label: "flight_detection.climbing_faster_than".tr(), max: 5, enabled: launchUseVario),
                  if (launchUseAgl && launchUseVario)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text("flight_detection.either_one".tr(),
                          style: const TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic)),
                    ),
                  _secondsSlider(settingsMgr.launchHoldTime, label: "flight_detection.hold_for".tr(), max: 60),
                  _toggle(settingsMgr.launchUseSp140Armed, title: "flight_detection.sp140_start".tr()),

                  const Divider(height: 32),

                  // --- Landing
                  _header(Icons.flight_land, "flight_detection.landing".tr(), "flight_detection.landing_help".tr()),
                  _unitSlider(settingsMgr.landingMaxSpeed, UnitType.speed,
                      label: "flight_detection.slower_than".tr(), max: 10),
                  _toggle(settingsMgr.landingUseVario,
                      title: "flight_detection.level".tr(), subtitle: "flight_detection.level_help".tr()),
                  _unitSlider(settingsMgr.landingMaxVario, UnitType.vario,
                      label: "flight_detection.vario_less_than".tr(),
                      max: 3,
                      enabled: settingsMgr.landingUseVario.value),
                  _toggle(settingsMgr.landingUseAgl,
                      title: "flight_detection.near_ground".tr(), subtitle: "flight_detection.near_ground_help".tr()),
                  _unitSlider(settingsMgr.landingMaxAgl, UnitType.distFine,
                      label: "flight_detection.lower_than".tr(), max: 300, enabled: settingsMgr.landingUseAgl.value),
                  _secondsSlider(settingsMgr.landingHoldTime, label: "flight_detection.hold_for".tr(), max: 120),
                  _toggle(settingsMgr.landingUseSp140Armed, title: "flight_detection.sp140_keep".tr()),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                    onPressed: () => setState(() => settingsMgr.resetFlightDetection()),
                    icon: const Icon(Icons.restore),
                    label: Text("flight_detection.reset".tr())),
                TextButton(onPressed: () => Navigator.pop(context), child: Text("btn.Ok".tr())),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
