import 'dart:math';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/dialogs/wind_dialog.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/services/ble_service.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/altimeter.dart';
import 'package:xcnav/widgets/windicator.dart';

/// Full screen view of the main instruments (speed, wind, altitude), sized for at-a-glance reading.
///
/// Tap the speed panel (or the close button) to return.
/// Tap the wind indicator to swap the wind details into its place.
class BigInstruments extends StatefulWidget {
  const BigInstruments({super.key});

  @override
  State<BigInstruments> createState() => _BigInstrumentsState();
}

class _BigInstrumentsState extends State<BigInstruments> {
  static const _tabular = [FontFeature.tabularFigures()];

  bool showWindDetails = false;

  @override
  Widget build(BuildContext context) {
    final unitColor = Colors.grey.shade400;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([myTelemetry, BleDeviceHandler.devicesChanged]),
          builder: (context, _) => OrientationBuilder(builder: (context, orientation) {
            final portrait = orientation == Orientation.portrait;
            final panels = [
              // Wind details need more room; the instruments scale down to make space.
              Expanded(flex: showWindDetails && !portrait ? 3 : 4, child: _altimeterPanel(unitColor)),
              Expanded(
                  flex: showWindDetails ? (portrait ? 4 : 6) : 3,
                  child: showWindDetails ? _windDetailsPanel() : _windPanel()),
              Expanded(flex: showWindDetails ? 2 : 3, child: _speedPanel(context, unitColor)),
              if (bleDeviceSp140.device != null) Expanded(flex: 2, child: _sp140Panel(unitColor)),
            ];
            return Stack(
              children: [
                portrait ? Column(children: panels) : Row(children: panels),
                Positioned(
                  left: 4,
                  top: 4,
                  child: IconButton(
                    key: const Key("bigInstruments_close"),
                    iconSize: 32,
                    color: Colors.white54,
                    icon: const Icon(Icons.close_fullscreen),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _panel({Key? key, required Widget child}) {
    return Container(
      key: key,
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox.expand(
          child: FittedBox(
              fit: BoxFit.contain,
              child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child))),
    );
  }

  // --- Speedometer
  Widget _speedPanel(BuildContext context, Color unitColor) {
    return GestureDetector(
      key: const Key("bigInstruments_speed"),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context),
      child: _panel(
        child: myTelemetry.geo != null
            ? Text.rich(richValue(UnitType.speed, myTelemetry.speedSmooth.value,
                digits: 3,
                autoDecimalThresh: -1,
                valueStyle: const TextStyle(fontSize: 200, fontFeatures: _tabular),
                unitStyle: TextStyle(fontSize: 50, color: unitColor)))
            : const Text("--", style: TextStyle(fontSize: 200)),
      ),
    );
  }

  // --- Windicator
  Widget _windPanel() {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: Windicator(
            myTelemetry: myTelemetry,
            size: max(90, min(constraints.maxWidth, constraints.maxHeight)),
            onTap: () => setState(() => showWindDetails = true),
          ),
        ),
      ),
    );
  }

  Widget _windDetailsPanel() {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        key: const Key("bigInstruments_windDetails"),
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: WindDialog(onClose: () => setState(() => showWindDetails = false)),
      ),
    );
  }

  // --- Altimeter stack
  Widget _altimeterPanel(Color unitColor) {
    return ValueListenableBuilder<AltimeterMode>(
      valueListenable: settingsMgr.primaryAltimeter.listenable,
      builder: (context, primaryAltimeter, _) {
        final geo = myTelemetry.geo;
        final msl = geo?.alt;
        final agl = (geo != null && geo.ground != null) ? geo.alt - geo.ground! : null;
        final isMsl = primaryAltimeter == AltimeterMode.msl;
        final vario = myTelemetry.varioSmooth.value;
        final showVario = vario.abs() > settingsMgr.altimeterVsiThresh.value;
        final varioColor = vario > 0 ? Colors.lightGreen : Colors.redAccent;

        return GestureDetector(
          key: const Key("bigInstruments_altimeter"),
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () {
            settingsMgr.primaryAltimeter.value = isMsl ? AltimeterMode.agl : AltimeterMode.msl;
          },
          child: _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Primary
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(_altStr(isMsl ? msl : agl),
                        style: const TextStyle(fontSize: 200, fontFeatures: _tabular, height: 1)),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AltimeterBadge(isMsl ? "MSL" : "AGL", size: 3),
                        Text(getUnitStr(UnitType.distFine), style: TextStyle(fontSize: 50, color: unitColor)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Vario + secondary
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Opacity(
                      opacity: showVario ? 1 : 0,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        RotatedBox(
                            quarterTurns: vario > 0 ? 0 : 2,
                            child: SvgPicture.asset("assets/images/arrow.svg",
                                height: 60, colorFilter: ColorFilter.mode(varioColor, BlendMode.srcIn))),
                        const SizedBox(width: 8),
                        Text.rich(TextSpan(children: [
                          TextSpan(
                              text: printValue(UnitType.vario, vario.abs(), digits: 3, decimals: 1),
                              style: TextStyle(fontSize: 60, color: varioColor, fontFeatures: _tabular)),
                          TextSpan(
                              text: " ${getUnitStr(UnitType.vario)}", style: TextStyle(fontSize: 30, color: unitColor)),
                        ])),
                      ]),
                    ),
                    const SizedBox(width: 48),
                    Text(_altStr(isMsl ? agl : msl), style: const TextStyle(fontSize: 70, fontFeatures: _tabular)),
                    const SizedBox(width: 8),
                    AltimeterBadge(isMsl ? "AGL" : "MSL", size: 2),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- SP140 (power, charge, endurance, cell balance)
  Widget _sp140Panel(Color unitColor) {
    final telemetry = bleDeviceSp140.telemetry;
    return _panel(
      key: const Key("bigInstruments_sp140"),
      // Every telemetry packet updates power, so it drives the rebuild for all values.
      child: StreamBuilder<double>(
        stream: telemetry.power.valueRawStream,
        initialData: telemetry.power.log.lastOrNull?.value,
        builder: (context, power) {
          final charge = telemetry.charge.log.lastOrNull?.value;
          final diffVolt = telemetry.diffVolt.value;
          final valueStyle = const TextStyle(fontSize: 120, fontFeatures: _tabular, height: 1);
          final unitStyle = TextStyle(fontSize: 50, color: unitColor);

          final fuelStat = myTelemetry.inFlight && myTelemetry.fuelReportController.fuelReports.isNotEmpty
              ? myTelemetry.fuelReportController.getSumFuelStat(myTelemetry.recordGeo)
              : null;
          final etaEmpty = fuelStat?.extrapolateEndurance(myTelemetry.fuelReportController.fuelReports.last,
              from: clock.now());
          final etaWarn = etaEmpty != null && etaEmpty < const Duration(minutes: 15);
          final etaStyle =
              valueStyle.copyWith(color: etaWarn ? Colors.red : null, fontWeight: etaWarn ? FontWeight.bold : null);

          final battery = batteryIcon(charge?.toDouble() ?? 0, 120);

          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: power.data?.toStringAsFixed(1) ?? "--", style: valueStyle),
                TextSpan(text: "kW", style: unitStyle),
              ])),
              const Icon(Icons.electric_bolt, size: 120, color: Colors.amber),
              const SizedBox(width: 48),
              Text.rich(TextSpan(children: [
                TextSpan(text: charge?.toString() ?? "--", style: valueStyle),
                TextSpan(text: "%", style: unitStyle),
              ])),
              // batteryIcon is styled for light backgrounds.
              Icon(battery.icon, size: 120, color: battery.color == Colors.black ? Colors.white : battery.color),
              if (etaEmpty != null) ...[
                const SizedBox(width: 48),
                Text.rich(richHrMin(duration: etaEmpty, valueStyle: etaStyle, unitStyle: unitStyle)),
                Icon(Icons.timer_outlined, size: 120, color: unitColor),
              ],
              if (diffVolt > 20) ...[
                const SizedBox(width: 48),
                Text.rich(TextSpan(children: [
                  TextSpan(text: "$diffVolt", style: valueStyle),
                  TextSpan(text: "mV", style: unitStyle),
                ])),
                Icon(Icons.battery_alert, size: 120, color: diffVolt > 200 ? Colors.red : unitColor),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _altStr(double? value) => printValue(UnitType.distFine, value, digits: 5, decimals: 0) ?? "--";
}
