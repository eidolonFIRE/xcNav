import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';

// Providers
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/settings.dart';

class SettingsEditor extends StatefulWidget {
  const SettingsEditor({Key? key}) : super(key: key);

  @override
  State<SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends State<SettingsEditor> {
  final TextEditingController searchInput = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Consumer<Settings>(builder: ((context, settings, child) {
      return Scaffold(
          appBar: AppBar(
            title: const Text("Settings"),
            // TODO: when we have enough settings, we can use a search
            // title: SizedBox(
            //   height: 32,
            //   child: TextField(
            //     style: const TextStyle(fontSize: 24),
            //     controller: searchInput,
            //     decoration:
            //         const InputDecoration(suffixIcon: Icon(Icons.search)),
            //   ),
            // ),
          ),
          body: SettingsList(
            sections: [
              SettingsSection(
                title: const Text("UI Options"),
                tiles: [
                  SettingsTile.switchTile(
                    initialValue: settings.mapControlsRightSide,
                    onToggle: (value) => settings.mapControlsRightSide = value,
                    title: const Text("Map Controls Right Side"),
                    leading: const Icon(Icons.swap_horiz),
                  )
                ],
              ),
              SettingsSection(
                  title: const Text(
                    "Debug Tools",
                    style: TextStyle(color: Colors.red),
                  ),
                  tiles: <SettingsTile>[
                    // --- Toggle: Location Spoofing
                    SettingsTile.switchTile(
                      initialValue: settings.spoofLocation,
                      title: const Text("Spoof Location"),
                      leading: const Icon(Icons.location_off),
                      onToggle: (value) => {settings.spoofLocation = value},
                    ),
                    // --- Erase Identity
                    SettingsTile.navigation(
                      title: const Text("Clear Identity"),
                      leading: const Icon(
                        Icons.warning_amber,
                        color: Colors.red,
                      ),
                      onPressed: (value) => {
                        showDialog(
                            context: context,
                            builder: (BuildContext ctx) {
                              return AlertDialog(
                                title: const Text('Please Confirm'),
                                content: const Text(
                                    'Are you sure you want to clear your Identity?'),
                                actions: [
                                  // The "Yes" button
                                  TextButton.icon(
                                      onPressed: () {
                                        // Remove the box
                                        Provider.of<Profile>(context,
                                                listen: false)
                                            .eraseIdentity();

                                        // Close the dialog
                                        Navigator.of(context).pop();
                                      },
                                      icon: const Icon(
                                        Icons.delete_forever,
                                        color: Colors.red,
                                      ),
                                      label: const Text('Yes')),
                                  TextButton(
                                      onPressed: () {
                                        // Close the dialog
                                        Navigator.of(context).pop();
                                      },
                                      child: const Text('No'))
                                ],
                              );
                            }),
                      },
                    )
                  ])
            ],
          ));
    }));
  }
}
