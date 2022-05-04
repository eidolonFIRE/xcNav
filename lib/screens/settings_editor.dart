import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

// Providers
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/settings.dart';

//
import 'package:xcnav/units.dart';

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
              // --- Display Units
              SettingsSection(title: const Text("Display Units"), tiles: [
                SettingsTile.navigation(
                  title: const Text("Fuel"),
                  trailing: DropdownButton<DisplayUnitsFuel>(
                      onChanged: (value) => {
                            settings.displayUnitsFuel =
                                value ?? DisplayUnitsFuel.liter
                          },
                      value: settings.displayUnitsFuel,
                      items: const [
                        DropdownMenuItem(
                            value: DisplayUnitsFuel.liter, child: Text("L")),
                        DropdownMenuItem(
                            value: DisplayUnitsFuel.gal, child: Text("Gal")),
                      ]),
                  leading: const Icon(Icons.local_gas_station),
                ),
                SettingsTile.navigation(
                  title: const Text("Distance"),
                  trailing: DropdownButton<DisplayUnitsDist>(
                      onChanged: (value) => {
                            settings.displayUnitsDist =
                                value ?? DisplayUnitsDist.imperial
                          },
                      value: settings.displayUnitsDist,
                      items: const [
                        DropdownMenuItem(
                            value: DisplayUnitsDist.imperial,
                            child: Text("Imperial")),
                        DropdownMenuItem(
                            value: DisplayUnitsDist.metric,
                            child: Text("Metric")),
                      ]),
                  leading: const Icon(Icons.architecture),
                ),
                SettingsTile.navigation(
                  title: const Text("Speed"),
                  trailing: DropdownButton<DisplayUnitsSpeed>(
                      onChanged: (value) => {
                            settings.displayUnitsSpeed =
                                value ?? DisplayUnitsSpeed.mph
                          },
                      value: settings.displayUnitsSpeed,
                      items: const [
                        DropdownMenuItem(
                            value: DisplayUnitsSpeed.mph, child: Text("mph")),
                        DropdownMenuItem(
                            value: DisplayUnitsSpeed.kph, child: Text("kph")),
                        DropdownMenuItem(
                            value: DisplayUnitsSpeed.kts, child: Text("kts")),
                        DropdownMenuItem(
                            value: DisplayUnitsSpeed.mps, child: Text("m/s")),
                      ]),
                  leading: const Icon(Icons.timer),
                ),
                SettingsTile.navigation(
                  title: const Text("Vario Unit"),
                  trailing: DropdownButton<DisplayUnitsVario>(
                      onChanged: (value) => {
                            settings.displayUnitsVario =
                                value ?? DisplayUnitsVario.fpm
                          },
                      value: settings.displayUnitsVario,
                      items: const [
                        DropdownMenuItem(
                            value: DisplayUnitsVario.fpm, child: Text("ft/m")),
                        DropdownMenuItem(
                            value: DisplayUnitsVario.mps, child: Text("m/s")),
                      ]),
                  leading: const Icon(Icons.trending_up),
                ),
              ]),
              // --- UI options
              SettingsSection(
                title: const Text("UI Options"),
                tiles: [
                  SettingsTile.switchTile(
                    initialValue: settings.mapControlsRightSide,
                    onToggle: (value) => settings.mapControlsRightSide = value,
                    title: const Text("Right-handed UI"),
                    leading: const Icon(Icons.swap_horiz),
                    description: const Text(
                        "Move map control buttons to the right side."),
                  ),
                  SettingsTile.switchTile(
                    initialValue: settings.groundMode,
                    onToggle: (value) => settings.groundMode = value,
                    title: const Text("Ground Support Mode"),
                    leading: const Icon(Icons.swap_horiz),
                    description:
                        const Text("Alters UI and doesn't record track."),
                  ),
                ],
              ),
              // --- ADSB options
              SettingsSection(title: const Text("ADSB"), tiles: [
                SettingsTile.navigation(
                  title: const Text("Proximity Profile"),
                  leading: const Icon(Icons.radar),
                  description: Text(
                      settings.proximityProfile.toMultilineString(settings)),
                  trailing: DropdownButton<String>(
                    onChanged: (value) {
                      settings.selectProximityConfig(value ?? "Medium");
                    },
                    value: settings.proximityProfileName,
                    items: settings.proximityProfileOptions.entries
                        .map((each) => DropdownMenuItem(
                            value: each.key, child: Text(each.key)))
                        .toList(),
                  ),
                )
              ]),

              // --- Debug Tools
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
                      leading: const Icon(
                        Icons.location_off,
                        color: Colors.red,
                      ),
                      onToggle: (value) => {settings.spoofLocation = value},
                    ),
                    // --- Erase Identity
                    SettingsTile.navigation(
                      title: const Text("Clear Identity"),
                      description: const Text(
                          "This will reset your pilot ID and profile!"),
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
                                        // Clear Profile
                                        Provider.of<Profile>(context,
                                                listen: false)
                                            .eraseIdentity();

                                        // Remove Avatar saved file
                                        path_provider
                                            .getTemporaryDirectory()
                                            .then((tempDir) {
                                          var outfile = File(
                                              tempDir.path + "/avatar.jpg");
                                          outfile.exists().then((value) =>
                                              {if (value) outfile.delete()});
                                        });

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
