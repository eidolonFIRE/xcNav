import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/ble_devices/ble_device_meshtastic.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/services/ble_service.dart' as ble_service;

/// Compact status of the links to the group (cellular, and Meshtastic when a radio is attached).
/// Tapping it opens the Meshtastic settings, where the links can be toggled.
class LinkStatusIcon extends StatelessWidget {
  const LinkStatusIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Provider.of<Client>(context);
    final meshtastic = ble_service.bleDeviceMeshtastic;

    final icons = <Widget>[
      Icon(
        client.cellularEnabled && client.state != ClientState.disconnected
            ? Icons.signal_cellular_alt
            : Icons.signal_cellular_off,
        key: const Key("linkStatus_cellular"),
        size: 26,
        color: cellularStatusColor(client),
      ),
      if (meshtastic.isActive)
        Icon(
          Icons.cell_tower,
          key: const Key("linkStatus_mesh"),
          size: 26,
          color: client.meshEnabled ? meshtasticStatusColor(meshtastic.status.value) : Colors.grey.shade600,
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
              child: Column(mainAxisSize: MainAxisSize.min, children: icons),
            ),
          ),
        ),
      ),
    );
  }
}

Color cellularStatusColor(Client client) {
  if (!client.cellularEnabled) return Colors.grey.shade600;
  switch (client.state) {
    case ClientState.authenticated:
      return Colors.black;
    case ClientState.connected:
      return Colors.amber.shade800;
    case ClientState.disconnected:
      return Colors.red;
  }
}
