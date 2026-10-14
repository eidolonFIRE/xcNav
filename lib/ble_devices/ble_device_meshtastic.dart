import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/datadog.dart' as dd;
import 'package:xcnav/models/meshtastic_proto.dart';
import 'package:xcnav/models/protobuf_lite.dart';
import 'package:xcnav/settings_service.dart';

enum MeshtasticStatus {
  disconnected,
  configuring,

  /// Radio has no LoRa region, so it won't transmit. We don't set region for the user.
  noRegion,

  /// Not in an xcNav group, so there is no channel to talk on.
  noGroup,

  /// Radio kept rejecting our settings.
  error,
  ready,
}

typedef MeshReceiveCallback = void Function(int fromNode, Uint8List payload);

/// Meshtastic radio connected over the Meshtastic BLE phone API.
/// https://meshtastic.org/docs/development/device/client-api/
///
/// xcNav takes over the radio's primary channel (derived from the group code) so everyone
/// in the group lands on the same channel and frequency slot. The LoRa preset is chosen by the user.
class BleDeviceMeshtastic extends BleDeviceHandler {
  @override
  // ignore: overridden_fields, non_constant_identifier_names
  final SERVICE_UUID = "6ba1b218-15a8-461f-9fa8-5dcae273eafd";
  static const _toRadioUuid = "f75c76d2-129e-4dad-a1dd-7866124401e7";
  static const _fromRadioUuid = "2c55e69e-4993-11ed-b878-0242ac120002";
  static const _fromNumUuid = "ed9da18c-a800-4f66-a670-aa7547e34453";
  static const _writeAttempts = 3;

  final ValueNotifier<MeshtasticStatus> status = ValueNotifier(MeshtasticStatus.disconnected);

  /// User has a radio selected (connected, or reconnecting after dropping out of BLE range).
  final ValueNotifier<bool> attached = ValueNotifier(false);

  BluetoothDevice? _device;

  @override
  BluetoothDevice? get device => _device;

  @override
  set device(BluetoothDevice? value) {
    _device = value;
    attached.value = value != null;
  }

  /// Called with the payload of xcNav packets received on the group channel.
  MeshReceiveCallback? onReceive;

  /// Our radio's node number
  int? myNodeNum;

  /// Last time each xcNav node was heard
  final Map<int, DateTime> lastHeard = {};

  PbMessage? _lora;
  final Map<int, PbMessage> _channels = {};
  String? _groupId;
  int _configNonce = 0;
  DateTime _configRequested = DateTime(0);
  int _configAttempts = 0;

  BluetoothCharacteristic? _toRadio;
  BluetoothCharacteristic? _fromRadio;
  StreamSubscription? _fromNumSub;
  StreamSubscription? _connectionSub;
  Timer? _pollTimer;
  bool _draining = false;
  bool _drainAgain = false;
  Future<void> _writeChain = Future.value();
  final Random _rand = Random();

  bool get isActive => attached.value;

  bool get isReady => status.value == MeshtasticStatus.ready;

  MeshPreset get preset => MeshPreset.fromValue(settingsMgr.meshtasticPreset.value) ?? MeshPreset.longFast;

  MeshGroupChannel? get groupChannel => _groupId == null ? null : MeshGroupChannel.forGroup(_groupId!);

  int get numNodesHeard =>
      lastHeard.values.where((e) => clock.now().difference(e) < const Duration(minutes: 5)).length;

  @override
  Widget configDialog() {
    return MeshtasticConfigDialog(meshtastic: this);
  }

  void setGroupId(String? groupId) {
    if (groupId == _groupId) return;
    _groupId = groupId;
    _configAttempts = 0;
    _ensureConfig();
  }

  void setPreset(MeshPreset newPreset) {
    settingsMgr.meshtasticPreset.value = newPreset.value;
    _configAttempts = 0;
    _ensureConfig();
  }

  /// Broadcast an xcNav payload on the group channel. Returns false if the radio isn't ready.
  bool send(Uint8List payload, {bool wantAck = false}) {
    if (!isReady || payload.length > meshMaxPayload) return false;
    _write(buildToRadioPacket(
      id: _newPacketId(),
      to: meshBroadcastAddr,
      portnum: xcNavPortNum,
      payload: payload,
      wantAck: wantAck,
      hopLimit: meshHopLimit,
    ));
    return true;
  }

  @override
  Future onConnected(BluetoothDevice instance) async {
    await super.onConnected(instance);
    _toRadio = characteristics[SERVICE_UUID]?[_toRadioUuid];
    _fromRadio = characteristics[SERVICE_UUID]?[_fromRadioUuid];
    final fromNum = characteristics[SERVICE_UUID]?[_fromNumUuid];
    if (_toRadio == null || _fromRadio == null || fromNum == null) {
      dd.warn("Meshtastic device missing characteristics", attributes: {"name": instance.advName});
      status.value = MeshtasticStatus.error;
      return;
    }

    if (Platform.isAndroid) {
      // Meshtastic needs an encrypted link. Without a bond, the first writes fail with GATT_ERROR (133)
      // while Android pairs in the background, so pair up front.
      try {
        if (await instance.bondState.first != BluetoothBondState.bonded) {
          debugPrint("Meshtastic: bonding with radio");
          await instance.createBond();
        }
      } catch (error) {
        dd.warn("Meshtastic bonding failed", attributes: {"error": error.toString()});
      }
      // onConnected can run before connect() finishes its MTU request. Make sure packets fit in one write.
      try {
        await instance.requestMtu(512);
      } catch (error) {
        debugPrint("Meshtastic: failed to request MTU: $error");
      }
    }

    _connectionSub?.cancel();
    _connectionSub = instance.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        onDisconnected();
      }
    });

    // Radio notifies on FromNum whenever it has packets queued for us.
    _fromNumSub?.cancel();
    _fromNumSub = fromNum.onValueReceived.listen((_) => _drain());
    try {
      await fromNum.setNotifyValue(true);
    } catch (error) {
      debugPrint("Meshtastic: failed to subscribe to FromNum: $error");
    }
    // Fallback in case a notification is missed.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // The first request can be lost while the OS is pairing with the radio.
      if (status.value == MeshtasticStatus.configuring &&
          clock.now().difference(_configRequested) > const Duration(seconds: 15)) {
        debugPrint("Meshtastic: no config received, asking again");
        _requestConfig();
      } else {
        _drain();
      }
    });

    _requestConfig();
  }

  @override
  void onDisconnected() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _fromNumSub?.cancel();
    _fromNumSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    _toRadio = null;
    _fromRadio = null;
    status.value = MeshtasticStatus.disconnected;
    // Only auto-reconnect if the user didn't disconnect us.
    if (device != null) super.onDisconnected();
  }

  int _newPacketId() => 1 + _rand.nextInt(0x7FFFFFFE);

  void _write(Uint8List bytes) {
    _writeChain = _writeChain.then((_) async {
      for (int attempt = 1;; attempt++) {
        final toRadio = _toRadio;
        if (toRadio == null) return;
        try {
          await toRadio.write(bytes, allowLongWrite: bytes.length > (device?.mtuNow ?? 23) - 3);
          return;
        } catch (error) {
          // Transient GATT errors happen while the link is still settling (pairing, MTU, radio rebooting).
          if (attempt >= _writeAttempts || !(device?.isConnected ?? false)) rethrow;
          debugPrint("Meshtastic: write failed (attempt $attempt), retrying: $error");
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }).catchError((error) {
      dd.error("Writing Meshtastic ToRadio", errorMessage: error.toString(), errorKind: "BLE");
    });
  }

  /// Ask the radio to dump its config. Answers stream back through FromRadio, ending in `config_complete_id`.
  void _requestConfig() {
    myNodeNum = null;
    _lora = null;
    _channels.clear();
    status.value = MeshtasticStatus.configuring;
    _configRequested = clock.now();
    do {
      _configNonce = 1 + _rand.nextInt(0x7FFFFFFE);
      // 69420 and 69421 are special nonces that skip parts of the config.
    } while (_configNonce == 69420 || _configNonce == 69421);
    _write(buildWantConfig(_configNonce));
    _drain();
  }

  /// Read FromRadio until it is empty.
  Future<void> _drain() async {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    final fromRadio = _fromRadio;
    if (fromRadio == null || !(device?.isConnected ?? false)) return;
    _draining = true;
    try {
      do {
        _drainAgain = false;
        // Let pending writes (e.g. want_config) land first.
        await _writeChain;
        while (true) {
          final bytes = await fromRadio.read();
          if (bytes.isEmpty) break;
          _handleFromRadio(bytes);
        }
      } while (_drainAgain && _fromRadio != null);
    } catch (error) {
      debugPrint("Meshtastic: error reading FromRadio: $error");
    } finally {
      _draining = false;
    }
  }

  void _handleFromRadio(List<int> bytes) {
    final PbMessage msg;
    try {
      msg = PbMessage.decode(bytes);
    } on FormatException catch (error) {
      debugPrint("Meshtastic: bad FromRadio: $error");
      return;
    }

    if (msg.has(FromRadioField.packet)) {
      final packet = msg.getMessage(FromRadioField.packet);
      if (packet != null) _handlePacket(packet);
    } else if (msg.has(FromRadioField.myInfo)) {
      myNodeNum = msg.getMessage(FromRadioField.myInfo)?.getInt(MyNodeInfoField.myNodeNum);
      debugPrint("Meshtastic: my node is ${myNodeNum?.toRadixString(16)}");
    } else if (msg.has(FromRadioField.config)) {
      final lora = msg.getMessage(FromRadioField.config)?.getMessage(ConfigField.lora);
      if (lora != null) _lora = lora;
    } else if (msg.has(FromRadioField.channel)) {
      final channel = msg.getMessage(FromRadioField.channel);
      if (channel != null) _channels[channel.getInt(ChannelField.index) ?? 0] = channel;
    } else if (msg.has(FromRadioField.configCompleteId)) {
      if (msg.getInt(FromRadioField.configCompleteId) == _configNonce) {
        debugPrint("Meshtastic: config download complete");
        _ensureConfig();
      }
    } else if (msg.has(FromRadioField.rebooted)) {
      _requestConfig();
    }
  }

  void _handlePacket(PbMessage packet) {
    final from = packet.getInt(MeshPacketField.from) ?? 0;
    // Packets we can't decrypt arrive without `decoded`.
    final data = packet.getMessage(MeshPacketField.decoded);
    if (data == null || from == myNodeNum) return;
    if (data.getInt(DataField.portnum) != xcNavPortNum) return;
    // Only listen on the group channel.
    if ((packet.getInt(MeshPacketField.channel) ?? 0) != 0 || !isReady) return;

    final payload = data.getBytes(DataField.payload);
    if (payload == null) return;
    lastHeard[from] = clock.now();
    onReceive?.call(from, payload);
  }

  void _sendAdmin(PbMessage admin) {
    _write(buildToRadioPacket(
      id: _newPacketId(),
      to: myNodeNum!,
      portnum: PortNum.admin,
      payload: admin.encode(),
    ));
  }

  /// Make sure the radio has the group channel and selected preset.
  void _ensureConfig() {
    final lora = _lora;
    if (myNodeNum == null || lora == null || _toRadio == null) return;

    if ((lora.getInt(LoRaConfigField.region) ?? 0) == 0) {
      status.value = MeshtasticStatus.noRegion;
      return;
    }

    final edits = <PbMessage>[];
    final newLora = loraWithPreset(lora, preset);
    if (newLora != null) {
      edits.add(adminSetLoRaConfig(newLora));
      _lora = newLora;
    }
    final group = groupChannel;
    if (group != null) {
      final newChannel = primaryChannelForGroup(_channels[0], group);
      if (newChannel != null) {
        edits.add(adminSetChannel(newChannel));
        _channels[0] = newChannel;
      }
    }

    if (edits.isNotEmpty) {
      _configAttempts++;
      if (_configAttempts > 3) {
        dd.warn("Meshtastic radio not accepting config");
        status.value = MeshtasticStatus.error;
        return;
      }
      debugPrint("Meshtastic: applying ${edits.length} config change(s)");
      // The radio may reboot to apply a new preset. We'll reconnect and verify when it comes back.
      _sendAdmin(adminBeginEdit());
      edits.forEach(_sendAdmin);
      _sendAdmin(adminCommitEdit());
    }

    status.value = group == null ? MeshtasticStatus.noGroup : MeshtasticStatus.ready;
  }
}

// ############################################################################
//
//     UI
//
// ############################################################################

String meshtasticStatusText(MeshtasticStatus status) {
  switch (status) {
    case MeshtasticStatus.disconnected:
      return "meshtastic.status_disconnected".tr();
    case MeshtasticStatus.configuring:
      return "meshtastic.status_configuring".tr();
    case MeshtasticStatus.noRegion:
      return "meshtastic.status_no_region".tr();
    case MeshtasticStatus.noGroup:
      return "meshtastic.status_no_group".tr();
    case MeshtasticStatus.error:
      return "meshtastic.status_error".tr();
    case MeshtasticStatus.ready:
      return "meshtastic.status_ready".tr();
  }
}

Color meshtasticStatusColor(MeshtasticStatus status) {
  switch (status) {
    case MeshtasticStatus.ready:
      return Colors.green;
    case MeshtasticStatus.configuring:
    case MeshtasticStatus.disconnected:
      return Colors.amber;
    case MeshtasticStatus.noRegion:
    case MeshtasticStatus.noGroup:
    case MeshtasticStatus.error:
      return Colors.red;
  }
}

class MeshtasticConfigDialog extends StatelessWidget {
  final BleDeviceMeshtastic meshtastic;

  const MeshtasticConfigDialog({super.key, required this.meshtastic});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("meshtastic.title".tr()),
      content: ListenableBuilder(
          listenable: Listenable.merge([
            meshtastic.status,
            settingsMgr.meshtasticPreset.listenable,
            settingsMgr.clientUseCellular.listenable,
            settingsMgr.clientUseMesh.listenable,
          ]),
          builder: (context, _) {
            final status = meshtastic.status.value;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // --- Status
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.cell_tower, color: meshtasticStatusColor(status)),
                title: Text(meshtasticStatusText(status)),
                subtitle: meshtastic.myNodeNum == null
                    ? null
                    : Text(
                        "${"meshtastic.node".tr()}: !${meshtastic.myNodeNum!.toRadixString(16).padLeft(8, "0")}   ${"meshtastic.pilots_heard".tr()}: ${meshtastic.numNodesHeard}"),
              ),

              // --- Channel
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tag),
                title: Text("meshtastic.channel".tr()),
                trailing: Text(meshtastic.groupChannel?.name ?? "-"),
              ),

              // --- Preset
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.speed),
                title: Text("meshtastic.preset".tr()),
                subtitle: Text("meshtastic.preset_hint".tr(), style: const TextStyle(fontSize: 12)),
                trailing: DropdownButton<MeshPreset>(
                    value: meshtastic.preset,
                    items: MeshPreset.values.map((e) => DropdownMenuItem(value: e, child: Text(e.label))).toList(),
                    onChanged: (value) {
                      if (value != null) meshtastic.setPreset(value);
                    }),
              ),

              const Divider(),

              // --- Client transports
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.signal_cellular_alt),
                title: Text("meshtastic.use_cellular".tr()),
                value: settingsMgr.clientUseCellular.value,
                onChanged: (value) => settingsMgr.clientUseCellular.value = value,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.cell_tower),
                title: Text("meshtastic.use_mesh".tr()),
                value: settingsMgr.clientUseMesh.value,
                onChanged: (value) => settingsMgr.clientUseMesh.value = value,
              ),
            ]);
          }),
    );
  }
}
