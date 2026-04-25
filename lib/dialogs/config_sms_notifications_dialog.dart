// ignore_for_file: use_build_context_synchronously

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_native_contact_picker/model/contact.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/dialogs/enter_phone_number_dialog.dart';
import 'package:xcnav/main.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/sms.dart';

Future<bool?> confirmTestSmsDialog(BuildContext context, String number) {
  return showDialog<bool?>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text("dialog.confirm.sms".tr()),
            content: Text("To: $number"),
            actions: [
              ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: Icon(Icons.send, color: Colors.blue),
                  label: Text("btn.Send".tr()))
            ],
          ));
  ;
}

void showConfigSmsNotificationsDialog(BuildContext context, SharedPreferences prefs) {
  showDialog(
      context: context,
      builder: (context) {
        final formkKey = GlobalKey<FormState>(debugLabel: "SMSNotificationFormKey");
        return StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                title: Text("SMS Notifications"),
                content: Form(
                  key: formkKey,
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    // --- Phone Numberss
                    Card(
                      margin: EdgeInsets.zero,
                      color: darkishColor,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                              if (settingsMgr.smsNotifyNumbers.value.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    "${"empty_list".tr()}...",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                            ] +
                            settingsMgr.smsNotifyNumbers.value.map<Widget>((String raw) {
                              final String? name = raw.contains(",") ? raw.split(",")[0].trim() : null;
                              final String number = raw.contains(",") ? raw.split(",")[1].trim() : raw.trim();
                              return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                IconButton(
                                    onPressed: () async {
                                      // Send test SMS
                                      final resp = await confirmTestSmsDialog(context, number);
                                      if (resp == true) {
                                        smsSendNotification(
                                            addresses: [raw],
                                            template: "[TEST] ${settingsMgr.smsNotifyTakeoffTemplate.value}",
                                            latlng: Provider.of<MyTelemetry>(context, listen: false).geo!.latlng,
                                            pilotName: settingsMgr.pilotName.value,
                                            waypoints: Provider.of<ActivePlan>(context, listen: false)
                                                .waypoints
                                                .values
                                                .toList());
                                        smsSendNotification(
                                            addresses: [raw],
                                            template: "[TEST] ${settingsMgr.smsNotifyLandingTemplate.value}",
                                            latlng: Provider.of<MyTelemetry>(context, listen: false).geo!.latlng,
                                            pilotName: settingsMgr.pilotName.value,
                                            waypoints: Provider.of<ActivePlan>(context, listen: false)
                                                .waypoints
                                                .values
                                                .toList());
                                      }
                                    },
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.send, color: Colors.blue)),
                                Card(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(name ?? number),
                                    )),
                                IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => {
                                          settingsMgr.smsNotifyNumbers.value = settingsMgr.smsNotifyNumbers.value
                                              .where((element) => element != raw)
                                              .toList(),
                                          setState(() {}),
                                        },
                                    icon: Icon(
                                      Icons.cancel,
                                      color: Colors.red,
                                    )),
                              ]);
                            }).toList() +
                            <Widget>[
                              // --- Enter new number
                              if (settingsMgr.smsNotifyNumbers.value.length < 6)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                        onPressed: () async {
                                          final result = await enterPhoneNumberDialog(context);
                                          if (result != null && result.isNotEmpty) {
                                            settingsMgr.smsNotifyNumbers.value = [
                                              ...settingsMgr.smsNotifyNumbers.value,
                                              result
                                            ];
                                            setState(() {});
                                          }
                                        },
                                        icon: Icon(Icons.dialpad, color: Colors.green)),
                                    IconButton(
                                        onPressed: () async {
                                          Contact? contact = await FlutterNativeContactPicker().selectPhoneNumber();
                                          if (contact != null) {
                                            String newEntry = (contact.fullName != null
                                                    ? "${contact.fullName},${contact.selectedPhoneNumber}"
                                                    : contact.selectedPhoneNumber) ??
                                                "";
                                            newEntry = newEntry.trim();
                                            if (newEntry.isNotEmpty) {
                                              settingsMgr.smsNotifyNumbers.value = [
                                                ...settingsMgr.smsNotifyNumbers.value,
                                                newEntry
                                              ];
                                              setState(() {});
                                            }
                                          }
                                        },
                                        icon: Icon(Icons.import_contacts, color: Colors.green)),
                                  ],
                                ),
                            ],
                      ),
                    ),
                    Container(
                      height: 10,
                    ),
                    // --- Config

                    ListTile(
                        visualDensity: VisualDensity.compact,
                        leading: Icon(Icons.flight_takeoff),
                        title: Text("Takeoff".tr()),
                        contentPadding: EdgeInsets.zero,
                        trailing: DropdownMenuFormField<String>(
                            width: 120,
                            initialSelection: settingsMgr.smsNotifyTakeoff.value,
                            dropdownMenuEntries: [
                              DropdownMenuEntry(value: "off", label: "Off".tr()),
                              DropdownMenuEntry(value: "on", label: "Always".tr()),
                            ],
                            onSelected: (value) => setState(() {
                                  settingsMgr.smsNotifyTakeoff.value = value ?? "off";
                                }))),
                    TextFormField(
                        initialValue: settingsMgr.smsNotifyTakeoffTemplate.value,
                        minLines: 1,
                        maxLines: 3,
                        onChanged: (value) => setState(() {
                              settingsMgr.smsNotifyTakeoffTemplate.value = value;
                            }),
                        decoration: InputDecoration(
                          constraints: BoxConstraints(),
                          labelText: "message_template".tr(),
                        )),

                    Divider(
                      height: 30,
                    ),
                    ListTile(
                        visualDensity: VisualDensity.compact,
                        leading: Icon(Icons.flight_land),
                        title: Text("Landing".tr()),
                        contentPadding: EdgeInsets.zero,
                        trailing: DropdownMenuFormField<String>(
                            width: 120,
                            initialSelection: settingsMgr.smsNotifyLanding.value,
                            // style: TextStyle(overflow: TextOverflow.clip),
                            dropdownMenuEntries: [
                              DropdownMenuEntry(value: "off", label: "Off".tr()),
                              DropdownMenuEntry(value: "on", label: "Always".tr()),
                              DropdownMenuEntry(value: "new", label: "not_at_lz_waypoint".tr())
                            ],
                            onSelected: (value) => setState(() {
                                  settingsMgr.smsNotifyLanding.value = value ?? "off";
                                }))),

                    TextFormField(
                        initialValue: settingsMgr.smsNotifyLandingTemplate.value,
                        minLines: 1,
                        maxLines: 3,
                        onChanged: (value) => setState(() {
                              settingsMgr.smsNotifyLandingTemplate.value = value;
                            }),
                        decoration: InputDecoration(
                          constraints: BoxConstraints(),
                          labelText: "message_template".tr(),
                        )),
                  ]),
                )));
      });
}
