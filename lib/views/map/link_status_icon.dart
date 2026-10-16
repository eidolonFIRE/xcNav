import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/ble_devices/ble_device_meshtastic.dart';
import 'package:xcnav/ble_devices/ble_device_stodeus.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/services/ble_service.dart' as ble_service;

/// Compact status of GPS fix and the links to the group (cellular, and Meshtastic when a radio is attached).
/// Also shows a BLE vario when one is attached.
/// Tapping it opens the Meshtastic settings, where the links can be toggled.
class LinkStatusIcon extends StatefulWidget {
  const LinkStatusIcon({super.key});

  @override
  State<LinkStatusIcon> createState() => _LinkStatusIconState();
}

class _LinkStatusIconState extends State<LinkStatusIcon> {
  /// Rebuilds periodically so a GPS fix that stops updating shows as lost.
  /// Only runs while the app is in the foreground, so it doesn't wake the app in the background or standby.
  Timer? _staleTimer;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.resumed) {
        _startStaleTimer();
        setState(() {});
      } else {
        _stopStaleTimer();
      }
    });
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) _startStaleTimer();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _stopStaleTimer();
    super.dispose();
  }

  void _startStaleTimer() {
    _staleTimer ??= Timer.periodic(const Duration(seconds: 10), (_) => setState(() {}));
  }

  void _stopStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final client = Provider.of<Client>(context);
    final meshtastic = ble_service.bleDeviceMeshtastic;
    final vario = ble_service.bleDeviceStodeus;

    final icons = <Widget>[
      ValueListenableBuilder<bool>(
        valueListenable: vario.attached,
        builder: (context, attached, _) => attached
            ? ValueListenableBuilder<VarioStatus>(
                valueListenable: vario.status,
                builder: (context, status, _) => Icon(
                  Icons.swap_vert,
                  key: const Key("linkStatus_vario"),
                  size: 24,
                  color: varioStatusColor(status),
                ),
              )
            : const SizedBox.shrink(),
      ),
      if (meshtastic.isActive)
        Icon(
          Icons.cell_tower,
          key: const Key("linkStatus_mesh"),
          size: 24,
          color: client.meshEnabled ? meshtasticStatusColor(meshtastic.status.value) : Colors.grey.shade600,
        ),
      ValueListenableBuilder<GpsFixQuality?>(
        valueListenable: myTelemetry.gpsFix,
        builder: (context, fix, _) {
          final strength = fix?.strength ?? GpsStrength.none;
          return Icon(
            gpsStrengthIcon(strength),
            key: const Key("linkStatus_gps"),
            size: 24,
            color: gpsStrengthColor(strength),
          );
        },
      ),
      Icon(
        cellularStatusIcon(client),
        key: const Key("linkStatus_cellular"),
        size: 24,
        color: cellularStatusColor(client),
      ),
    ];

    return GestureDetector(
      onTap: meshtastic.isActive
          ? () => showDialog(context: context, builder: (context) => MeshtasticConfigDialog(meshtastic: meshtastic))
          : null,
      child: Container(
        foregroundDecoration: BoxDecoration(
            border: Border.all(width: 0.5, color: Colors.black),
            borderRadius: const BorderRadius.all(Radius.circular(12))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Container(
              color: Colors.white38,
              padding: const EdgeInsets.all(4),
              child: Row(mainAxisSize: MainAxisSize.min, children: icons),
            ),
          ),
        ),
      ),
    );
  }
}

IconData gpsStrengthIcon(GpsStrength strength) {
  switch (strength) {
    case GpsStrength.none:
      return Icons.gps_off;
    case GpsStrength.poor:
    case GpsStrength.fair:
      return Icons.gps_not_fixed;
    case GpsStrength.good:
      return Icons.gps_fixed;
  }
}

Color gpsStrengthColor(GpsStrength strength) {
  switch (strength) {
    case GpsStrength.none:
      return Colors.red;
    case GpsStrength.poor:
      return Colors.deepOrange;
    case GpsStrength.fair:
      return Colors.amber.shade800;
    case GpsStrength.good:
      return Colors.green;
  }
}

Color varioStatusColor(VarioStatus status) {
  switch (status) {
    case VarioStatus.disconnected:
      return Colors.red;
    case VarioStatus.connected:
      return Colors.amber.shade800;
    case VarioStatus.receiving:
      return Colors.green;
  }
}

IconData cellularStatusIcon(Client client) {
  if (!client.cellularEnabled) return Icons.signal_cellular_off;
  if (client.state == ClientState.authenticated) return Icons.signal_cellular_alt;
  if (client.cellularConnecting) return Icons.signal_cellular_connected_no_internet_4_bar;
  return Icons.signal_cellular_nodata;
}

Color cellularStatusColor(Client client) {
  if (!client.cellularEnabled) return Colors.grey.shade800;
  if (client.state == ClientState.authenticated) return Colors.green;
  if (client.cellularConnecting) return Colors.amber.shade800;
  return Colors.red;
}
