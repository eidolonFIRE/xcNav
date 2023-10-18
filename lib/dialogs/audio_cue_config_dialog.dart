import 'package:flutter/material.dart';
import 'package:xcnav/audio_cue_service.dart';

Future<Map<String, bool>?> showAudioCueConfigDialog(BuildContext context, Map<String, bool> config) {
  return showDialog<Map<String, bool>>(
    context: context,
    builder: (context) => StatefulBuilder(
        builder: ((context, setState) => SimpleDialog(
            children:
                // --- Each Entry
                config.entries
                        .map<Widget>((entry) => SwitchListTile(
                            value: entry.value,
                            secondary: Icon(AudioCueService.icons[entry.key]),
                            title: Text(entry.key),
                            onChanged: (newValue) => setState(
                                  () => config[entry.key] = newValue,
                                )))
                        .toList() +
                    [
                      // --- Accept Changes
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 16, top: 16),
                          child: IconButton(
                              icon: const Icon(Icons.check, color: Colors.lightGreen),
                              onPressed: () => Navigator.pop(context, config)),
                        )
                      ])
                    ]))),
  );
}
