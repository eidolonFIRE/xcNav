import 'dart:math';
import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/ble_devices/ble_device_big_battery.dart';
import 'package:xcnav/ble_devices/ble_device_runleader.dart';
import 'package:xcnav/ble_devices/ble_device_sp140.dart';
import 'package:xcnav/ble_devices/ble_device_xc170.dart';
import 'package:xcnav/dialogs/edit_live_fuel_report.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/services/ble_service.dart' as ble_service;
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/chat_bubble.dart';
import 'package:xcnav/widgets/map_button.dart';

/// Secondary column of map overlays (fuel, chat bubbles, BLE device cards).
/// Stacks from the bottom up on the opposite side from the map view buttons.
class MapStatusColumn extends StatelessWidget {
  const MapStatusColumn({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild when BLE devices attach/detach and on telemetry changes (e.g. inFlight gates the endurance rows).
    return ListenableBuilder(
        listenable: Listenable.merge([BleDeviceHandler.devicesChanged, myTelemetry]),
        builder: (context, _) => _buildColumn());
  }

  Widget _buildColumn() {
    return LayoutBuilder(builder: (context, constaints) {
      final buttonSize = max(30, min(60, constaints.maxHeight / 8)).toDouble();
      return Align(
        alignment: Alignment.bottomRight,
        child: Column(
          verticalDirection: VerticalDirection.up,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment:
              settingsMgr.mapControlsRightSide.value ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            // --- fuel button
            if (ble_service.bleDeviceSp140.device == null && ble_service.bleDeviceXc170.device == null)
              Align(
                  alignment: Alignment.bottomRight,
                  child: Column(mainAxisSize: MainAxisSize.min, verticalDirection: VerticalDirection.up, children: [
                    MapButton(
                      size: buttonSize,
                      selected: false,
                      child: const Icon(Icons.local_gas_station, color: Colors.black, size: 30),
                      onPressed: () => {editLiveFuelReport(context)},
                    ),
                    SizedBox(
                        width: 2,
                        height: buttonSize / 6,
                        child: Container(
                          color: Colors.black,
                        )),
                    const FuelRemainingBadge(),
                  ])),

            // --- Chat bubbles
            const MapChatBubbles(),

            // --- BLE xc170
            if (ble_service.bleDeviceXc170.device != null) Xc170StatusCard(xc170: ble_service.bleDeviceXc170),

            // --- Big Battery
            if (ble_service.bleDeviceBigBattery.device != null)
              BigBatteryStatusCard(bigBattery: ble_service.bleDeviceBigBattery),

            // --- Runleader
            if (ble_service.bleDeviceRunleader.device != null)
              RunleaderStatusCard(runleader: ble_service.bleDeviceRunleader),

            // --- Sp140
            if (ble_service.bleDeviceSp140.device != null) Sp140StatusCard(sp140: ble_service.bleDeviceSp140),
          ],
        ),
      );
    });
  }
}

/// Fuel remaining (or endurance time when in flight with a burn rate).
class FuelRemainingBadge extends StatelessWidget {
  const FuelRemainingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: myTelemetry,
        builder: (context, _) {
          return Container(
            foregroundDecoration: BoxDecoration(
                border: Border.all(width: 0.5, color: Colors.black),
                borderRadius: const BorderRadius.all(Radius.circular(15))),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                    child: Container(color: Colors.white38, child: _buildContent()))),
          );
        });
  }

  Widget _buildContent() {
    final fuelReport = myTelemetry.fuelReportController.fuelReports.lastOrNull;

    if (fuelReport != null) {
      if (myTelemetry.fuelReportController.getSumFuelStat(myTelemetry.recordGeo) == null || !myTelemetry.inFlight) {
        final warn = fuelReport.amount <= 1;
        final style = TextStyle(
            color: warn ? Colors.red : Colors.black,
            fontSize: 20,
            fontWeight: warn ? FontWeight.bold : FontWeight.normal);
        return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text.rich(
                richValue(UnitType.fuel, fuelReport.amount, decimals: 1, autoDecimalThresh: 2, valueStyle: style)));
      } else {
        final etaEmpty = myTelemetry.fuelReportController
            .getSumFuelStat(myTelemetry.recordGeo)!
            .extrapolateEndurance(fuelReport, from: clock.now());

        final warn = etaEmpty < const Duration(minutes: 15);
        final style = TextStyle(
            color: warn ? Colors.red : Colors.black,
            fontSize: 20,
            fontWeight: warn ? FontWeight.bold : FontWeight.normal);
        return Padding(
            padding: const EdgeInsets.all(8.0), child: Text.rich(richHrMin(duration: etaEmpty, valueStyle: style)));
      }
    } else {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text(
          "?",
          style: TextStyle(color: Colors.black, fontSize: 20),
        ),
      );
    }
  }
}

/// Recent chat messages from other pilots, which clear themselves after a short time.
class MapChatBubbles extends StatelessWidget {
  const MapChatBubbles({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatMessages>(
      builder: (context, chat, child) {
        // get valid bubbles
        const numSeconds = 20;
        final bubbles = <Widget>[];
        for (int i = chat.messages.length - 1; i >= 0; i--) {
          if (chat.messages[i].timestamp >
                  max(DateTime.now().millisecondsSinceEpoch - 1000 * numSeconds, chat.chatLastOpened) &&
              chat.messages[i].pilotId != Provider.of<Profile>(context, listen: false).id) {
            final message = chat.messages[i];
            bubbles.add(
              AutoClearChatBubble(
                false,
                !settingsMgr.mapControlsRightSide.value,
                message.text,
                AvatarRound(Provider.of<Group>(context, listen: false).pilots[message.pilotId]?.avatar, 20),
                null,
                message.timestamp,
                maxWidth: MediaQuery.of(context).size.width - 150,
                duration: const Duration(seconds: numSeconds),
                onExpire: () => chat.refresh(),
              ),
            );
          } else {
            break;
          }
        }
        return Column(
          verticalDirection: VerticalDirection.up,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment:
              settingsMgr.mapControlsRightSide.value ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: bubbles,
        );
      },
    );
  }
}
