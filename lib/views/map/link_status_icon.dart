import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/ble_devices/ble_device_meshtastic.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/services/ble_service.dart' as ble_service;

/// Compact status of GPS fix and the links to the group (cellular, and Meshtastic when a radio is attached).
/// Tapping it opens the Meshtastic settings, where the links can be toggled.
class LinkStatusIcon extends StatefulWidget {
  const LinkStatusIcon({super.key});

  @override
  State<LinkStatusIcon> createState() => _LinkStatusIconState();
}

class _LinkStatusIconState extends State<LinkStatusIcon> {
  /// Rebuilds periodically so a GPS fix that stops updating shows as lost.
  Timer? _staleTimer;

  @override
  void initState() {
    super.initState();
    _staleTimer = Timer.periodic(const Duration(seconds: 2), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = Provider.of<Client>(context);
    final meshtastic = ble_service.bleDeviceMeshtastic;

    final icons = <Widget>[
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
