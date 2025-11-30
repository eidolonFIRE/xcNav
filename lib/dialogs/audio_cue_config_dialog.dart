import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/dialogs/elevation_triggers_dialog.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/widgets/altimeter.dart';

void showAudioCueConfigDialog(BuildContext context) {
  showDialog<Map<String, bool>>(
    context: context,
    builder: (context) => StatefulBuilder(
        builder: ((context, setState) => SimpleDialog(
            children:
                // --- Each Entry
                audioCueService.config.entries
                    .map<Widget>((entry) => SwitchListTile(
                        value: entry.value,
                        secondary: Icon(AudioCueService.icons[entry.key]),
                        title: Text("audio_cue.${entry.key}".tr()),
                        onChanged: (newValue) => setState(
                              () => audioCueService.config[entry.key] = newValue,
                            )))
                    .toList()
                  ..insert(
                      1,
                      ValueListenableBuilder(
                          valueListenable: settingsMgr.audioCueAltimeter.listenable,
                          builder: (context, value, _) {
                            return ListTile(
                              leading: settingsMgr.audioCueAltimeter.icon,
                              title: Text(settingsMgr.audioCueAltimeter.title),
                              trailing: DropdownButton<AltimeterMode>(
                                  onChanged: (newValue) => {
                                        settingsMgr.audioCueAltimeter.value =
                                            newValue ?? settingsMgr.audioCueAltimeter.defaultValue
                                      },
                                  value: value,
                                  items: const [
                                    DropdownMenuItem(value: AltimeterMode.msl, child: Text("MSL")),
                                    DropdownMenuItem(value: AltimeterMode.agl, child: Text("AGL")),
                                  ]),
                            );
                          }))
                  ..add(ListTile(
                    leading: Icon(Icons.list),
                    title: Text("Custom Triggers"),
                    trailing: IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                          showElevationTriggersDialog(context);
                        },
                        icon: Icon(Icons.edit)),
                  ))))),
  );
}
