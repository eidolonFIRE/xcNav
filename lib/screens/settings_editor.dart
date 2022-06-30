import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:email_validator/email_validator.dart';

// Providers
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/providers/adsb.dart';

//
import 'package:xcnav/units.dart';
import 'package:xcnav/dialogs/patreon_info.dart';
import 'package:xcnav/providers/my_telemetry.dart';

class SettingsEditor extends StatefulWidget {
  const SettingsEditor({Key? key}) : super(key: key);

  @override
  State<SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends State<SettingsEditor> {
  final TextEditingController searchInput = TextEditingController();
  var emailFormKey = GlobalKey<FormState>();

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
            darkTheme: SettingsThemeData(
                settingsListBackground: Theme.of(context).backgroundColor,
                settingsSectionBackground: Colors.grey.shade900),
            platform: DevicePlatform.iOS,
            sections: [
              // --- Display Units
              SettingsSection(title: const Text("Display Units"), tiles: [
                SettingsTile.navigation(
                  title: const Text("Fuel"),
                  trailing: DropdownButton<DisplayUnitsFuel>(
                      onChanged: (value) => {settings.displayUnitsFuel = value ?? DisplayUnitsFuel.liter},
                      value: settings.displayUnitsFuel,
                      items: const [
                        DropdownMenuItem(value: DisplayUnitsFuel.liter, child: Text("L")),
                        DropdownMenuItem(value: DisplayUnitsFuel.gal, child: Text("Gal")),
                      ]),
                  leading: const Icon(Icons.local_gas_station),
                ),
                SettingsTile.navigation(
                  title: const Text("Distance"),
                  trailing: DropdownButton<DisplayUnitsDist>(
                      onChanged: (value) => {settings.displayUnitsDist = value ?? DisplayUnitsDist.imperial},
                      value: settings.displayUnitsDist,
                      items: const [
                        DropdownMenuItem(value: DisplayUnitsDist.imperial, child: Text("Imperial")),
                        DropdownMenuItem(value: DisplayUnitsDist.metric, child: Text("Metric")),
                      ]),
                  leading: const Icon(Icons.architecture),
                ),
                SettingsTile.navigation(
                  title: const Text("Speed"),
                  trailing: DropdownButton<DisplayUnitsSpeed>(
                      onChanged: (value) => {settings.displayUnitsSpeed = value ?? DisplayUnitsSpeed.mph},
                      value: settings.displayUnitsSpeed,
                      items: const [
                        DropdownMenuItem(value: DisplayUnitsSpeed.mph, child: Text("mph")),
                        DropdownMenuItem(value: DisplayUnitsSpeed.kph, child: Text("kph")),
                        DropdownMenuItem(value: DisplayUnitsSpeed.kts, child: Text("kts")),
                        DropdownMenuItem(value: DisplayUnitsSpeed.mps, child: Text("m/s")),
                      ]),
                  leading: const Icon(Icons.timer),
                ),
                SettingsTile.navigation(
                  title: const Text("Vario"),
                  trailing: DropdownButton<DisplayUnitsVario>(
                      onChanged: (value) => {settings.displayUnitsVario = value ?? DisplayUnitsVario.fpm},
                      value: settings.displayUnitsVario,
                      items: const [
                        DropdownMenuItem(value: DisplayUnitsVario.fpm, child: Text("ft/m")),
                        DropdownMenuItem(value: DisplayUnitsVario.mps, child: Text("m/s")),
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
                    // description: const Text(
                    //     "Move map control buttons to the right side."),
                  ),
                  SettingsTile.switchTile(
                    initialValue: settings.showPilotNames,
                    onToggle: (value) => settings.showPilotNames = value,
                    title: const Text("Always Show Pilot Names"),
                    leading: const Icon(Icons.abc),
                    // description: const Text(
                    //     "Move map control buttons to the right side."),
                  ),
                  SettingsTile.switchTile(
                    initialValue: settings.groundMode,
                    onToggle: (value) => settings.groundMode = value,
                    title: const Text("Ground Support Mode"),
                    leading: const Icon(Icons.directions_car),
                    // description:
                    //     const Text("Alters UI and doesn't record track."),
                  ),
                ],
              ),
              // --- ADSB options
              SettingsSection(title: const Text("ADSB"), tiles: [
                SettingsTile.navigation(
                  title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("Proximity Profile"),
                    // const Divider(),
                    Text(
                      settings.proximityProfile.toMultilineString(settings),
                      style: const TextStyle(fontSize: 12, color: Colors.white60),
                    )
                  ]),
                  leading: const Icon(Icons.radar),
                  trailing: DropdownButton<String>(
                    onChanged: (value) {
                      settings.selectProximityConfig(value ?? "Medium");
                    },
                    value: settings.proximityProfileName,
                    items: settings.proximityProfileOptions.entries
                        .map((each) => DropdownMenuItem(value: each.key, child: Text(each.key)))
                        .toList(),
                  ),
                ),
                // --- Test Audio
                SettingsTile.navigation(
                  title: const Text("Test Warning Audio"),
                  leading: const Icon(Icons.volume_up),
                  onPressed: (event) => {Provider.of<ADSB>(context, listen: false).testWarning()},
                ),
              ]),

              /// --- Patreon Info
              // TODO: validation should consider both fields at the same time... need both or neither
              SettingsSection(
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Patreon Identity"),
                      IconButton(
                          onPressed: () => {showPatreonInfoDialog(context)},
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          icon: const Icon(
                            Icons.help,
                            size: 20,
                            color: Colors.lightBlue,
                          ))
                    ],
                  ),
                  tiles: [
                    SettingsTile.navigation(
                      title: TextFormField(
                          initialValue: settings.patreonName,
                          decoration: const InputDecoration(label: Text("First Name")),
                          onFieldSubmitted: (value) {
                            settings.patreonName = value;
                          }),
                      trailing: Container(),
                    ),
                    SettingsTile.navigation(
                      title: Form(
                        key: emailFormKey,
                        child: TextFormField(
                          initialValue: settings.patreonEmail,
                          validator: (value) =>
                              EmailValidator.validate(value ?? "") || value == "" ? null : "Not a valid email",
                          decoration: const InputDecoration(label: Text("Email")),
                          onFieldSubmitted: (value) {
                            if (emailFormKey.currentState?.validate() ?? false) {
                              settings.patreonEmail = value;
                            }
                          },
                        ),
                      ),
                      trailing: Container(),
                    ),
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
                    // --- Clear path
                    SettingsTile.navigation(
                      title: const Text("Clear Current Flight"),
                      leading: const Icon(
                        Icons.delete_sweep,
                        color: Colors.red,
                      ),
                      onPressed: (_) {
                        Provider.of<MyTelemetry>(context, listen: false).recordGeo.clear();
                        Provider.of<MyTelemetry>(context, listen: false).flightTrace.clear();
                      },
                    ),
                    // --- Erase Identity
                    SettingsTile.navigation(
                      title: const Text("Clear Identity"),
                      // description: const Text(
                      //     "This will reset your pilot ID and profile!"),
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
                                content: const Text('Are you sure you want to clear your Identity?'),
                                actions: [
                                  // The "Yes" button
                                  ElevatedButton.icon(
                                      onPressed: () {
                                        // Clear Profile
                                        Provider.of<Profile>(context, listen: false).eraseIdentity();

                                        // Remove Avatar saved file
                                        path_provider.getTemporaryDirectory().then((tempDir) {
                                          var outfile = File(tempDir.path + "/avatar.jpg");
                                          outfile.exists().then((value) => {if (value) outfile.delete()});
                                        });

                                        // Close the dialog
                                        Navigator.of(context).pop();
                                      },
                                      icon: const Icon(
                                        Icons.delete_forever,
                                        color: Colors.red,
                                      ),
                                      label: const Text('Yes')),
                                  ElevatedButton(
                                      onPressed: () {
                                        // Close the dialog
                                        Navigator.of(context).pop();
                                      },
                                      child: const Text('No'))
                                ],
                              );
                            }),
                      },
                    ),
                    // --- Erase all cached avatars
                    SettingsTile.navigation(
                      title: const Text("Clear cached avatars"),
                      leading: const Icon(
                        Icons.account_circle,
                        color: Colors.red,
                      ),
                      onPressed: (value) => {
                        showDialog(
                            context: context,
                            builder: (BuildContext ctx) {
                              return AlertDialog(
                                title: const Text('Please Confirm'),
                                content: const Text('Are you sure you want to clear all cached avatars?'),
                                actions: [
                                  // The "Yes" button
                                  ElevatedButton.icon(
                                      onPressed: () {
                                        // // Clear Profile
                                        // Provider.of<Profile>(context, listen: false).eraseIdentity();

                                        // // Remove Avatar saved file
                                        // path_provider.getTemporaryDirectory().then((tempDir) {
                                        //   var outfile = File(tempDir.path + "/avatar.jpg");
                                        //   outfile.exists().then((value) => {if (value) outfile.delete()});
                                        // });
                                        path_provider.getTemporaryDirectory().then((tempDir) {
                                          var fileAvatar = Directory("${tempDir.path}/avatars/");
                                          fileAvatar.delete(recursive: true);
                                        });

                                        // Close the dialog
                                        Navigator.of(context).pop();
                                      },
                                      icon: const Icon(
                                        Icons.delete_forever,
                                        color: Colors.red,
                                      ),
                                      label: const Text('Yes')),
                                  ElevatedButton(
                                      onPressed: () {
                                        // Close the dialog
                                        Navigator.of(context).pop();
                                      },
                                      child: const Text('No'))
                                ],
                              );
                            }),
                      },
                    ),
                  ]),
              SettingsSection(tiles: [
                SettingsTile(
                    title: const Text("xcNav Version"),
                    trailing: FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, version) =>
                            Text("${version.data?.version ?? "?"} - ( ${version.data?.buildNumber ?? "?"} )")))
              ]),
            ],
          ));
    }));
  }
}
