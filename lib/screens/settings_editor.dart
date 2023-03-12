import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:email_validator/email_validator.dart';
import 'package:xcnav/endpoint.dart';
import 'package:xcnav/map_service.dart';

// Providers
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/providers/adsb.dart';

//
import 'package:xcnav/units.dart';
import 'package:xcnav/dialogs/patreon_info.dart';

class SettingsEditor extends StatefulWidget {
  const SettingsEditor({Key? key}) : super(key: key);

  @override
  State<SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends State<SettingsEditor> {
  final TextEditingController searchInput = TextEditingController();
  var emailFormKey = GlobalKey<FormState>();

  final filterText = TextEditingController();

  @override
  Widget build(BuildContext context) {
    // --- Future Builders
    getMapTileCacheSize().then((value) {
      setState(() {
        settingsMgr.clearMapCache.title = "Clear Map Cache ($value)";
      });
    });

    // --- Hookup actions
    settingsMgr.clearMapCache.callback = () {
      setState(() {
        emptyMapTileCache();
      });
    };

    settingsMgr.adsbTestAudio.callback = () {
      Provider.of<ADSB>(context, listen: false).testWarning();
    };

    return Scaffold(
        appBar: AppBar(
          title: const Text("Settings"),
        ),
        body: Column(
          children: [
            TextField(
              autofocus: false,
              // focusNode: textFocusNode,
              style: const TextStyle(fontSize: 20),
              controller: filterText,
              decoration: InputDecoration(
                  contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                  hintText: "search"),
              onChanged: (value) {
                setState(() {});
              },
            ),
            const Divider(),
            Expanded(
              child: ListView(
                  children: settingsMgr.settings
                      .map((key, catagory) => MapEntry(
                          key,

                          // Catagory
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 20, top: 20),
                                child: Text(
                                  key,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                              Card(
                                shape:
                                    const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                                color: Colors.grey.shade900,
                                margin: const EdgeInsets.all(8),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: ListTile.divideTiles(
                                        context: context,
                                        tiles: catagory
                                            .where((element) =>
                                                filterText.text.isEmpty ||
                                                weightedRatio(element.title, filterText.text) > 70)
                                            .map((e) => e.isConfig
                                                // --- Config
                                                ? ValueListenableBuilder(
                                                    valueListenable: e.config!.listenable,
                                                    builder: (context, value, _) {
                                                      Widget? trailing;
                                                      // Select trailing
                                                      switch (e.config!.value.runtimeType) {
                                                        case bool:
                                                          trailing = Switch.adaptive(
                                                              value: value as bool,
                                                              onChanged: (value) => e.config!.value = value);
                                                          break;
                                                        // TODO: generalize this. Blocker is getting enum.values from generic
                                                        case DisplayUnitsDist:
                                                          trailing = DropdownButton<DisplayUnitsDist>(
                                                              onChanged: (value) =>
                                                                  {e.config!.value = value ?? e.config!.defaultValue},
                                                              value: e.config!.value,
                                                              items: const [
                                                                DropdownMenuItem(
                                                                    value: DisplayUnitsDist.imperial,
                                                                    child: Text("Imperial")),
                                                                DropdownMenuItem(
                                                                    value: DisplayUnitsDist.metric,
                                                                    child: Text("Metric")),
                                                              ]);
                                                          break;
                                                        case DisplayUnitsSpeed:
                                                          trailing = DropdownButton<DisplayUnitsSpeed>(
                                                              onChanged: (value) =>
                                                                  {e.config!.value = value ?? e.config!.defaultValue},
                                                              value: e.config!.value,
                                                              items: const [
                                                                DropdownMenuItem(
                                                                    value: DisplayUnitsSpeed.mph, child: Text("mph")),
                                                                DropdownMenuItem(
                                                                    value: DisplayUnitsSpeed.kph, child: Text("kph")),
                                                                DropdownMenuItem(
                                                                    value: DisplayUnitsSpeed.kts, child: Text("kts")),
                                                                DropdownMenuItem(
                                                                    value: DisplayUnitsSpeed.mps, child: Text("m/s")),
                                                              ]);
                                                          break;
                                                        case DisplayUnitsVario:
                                                          trailing = DropdownButton<DisplayUnitsVario>(
                                                              onChanged: (value) =>
                                                                  {e.config!.value = value ?? e.config!.defaultValue},
                                                              value: e.config!.value,
                                                              items: const [
                                                                DropdownMenuItem(
                                                                    value: DisplayUnitsVario.fpm, child: Text("ft/m")),
                                                                DropdownMenuItem(
                                                                    value: DisplayUnitsVario.mps, child: Text("m/s")),
                                                              ]);
                                                          break;
                                                        case DisplayUnitsFuel:
                                                          trailing = DropdownButton<DisplayUnitsFuel>(
                                                              onChanged: (value) =>
                                                                  {e.config!.value = value ?? e.config!.defaultValue},
                                                              value: e.config!.value,
                                                              items: const [
                                                                DropdownMenuItem(
                                                                    value: DisplayUnitsFuel.liter, child: Text("L")),
                                                                DropdownMenuItem(
                                                                    value: DisplayUnitsFuel.gal, child: Text("Gal")),
                                                              ]);
                                                          break;
                                                        default:
                                                          trailing = Text(
                                                              "${e.config!.id} Unsupported Type ${e.config!.value.runtimeType}");
                                                      }
                                                      // Build each
                                                      return ListTile(
                                                        leading: e.config!.icon,
                                                        title: Text(
                                                          e.title,
                                                          style: Theme.of(context).textTheme.bodyText1,
                                                        ),
                                                        trailing: trailing,
                                                      );
                                                    })
                                                // --- Actions
                                                : ListTile(
                                                    title: Text(
                                                      e.title,
                                                      style: Theme.of(context).textTheme.bodyText1,
                                                    ),
                                                    trailing: IconButton(
                                                        icon: e.action!.actionIcon ?? const Icon(Icons.navigate_next),
                                                        onPressed: e.action!.callback),
                                                  ))).toList()),
                              ),
                            ],
                          )))
                      .values
                      .toList()),
            ),
          ],
        )

        // SettingsList(
        //   darkTheme: SettingsThemeData(
        //       settingsListBackground: Theme.of(context).backgroundColor,
        //       settingsSectionBackground: Colors.grey.shade900),
        //   platform: DevicePlatform.iOS,
        //   sections: [
        //     // --- Display Units
        //     SettingsSection(title: const Text("Display Units"), tiles: [
        //       SettingsTile.navigation(
        //         title: const Text("Fuel"),
        //         trailing: DropdownButton<DisplayUnitsFuel>(
        //             onChanged: (value) => {settings.displayUnitsFuel = value ?? DisplayUnitsFuel.liter},
        //             value: settings.displayUnitsFuel,
        //             items: const [
        //               DropdownMenuItem(value: DisplayUnitsFuel.liter, child: Text("L")),
        //               DropdownMenuItem(value: DisplayUnitsFuel.gal, child: Text("Gal")),
        //             ]),
        //         leading: const Icon(Icons.local_gas_station),
        //       ),
        //       SettingsTile.navigation(
        //         title: const Text("Distance"),
        //         trailing: DropdownButton<DisplayUnitsDist>(
        //             onChanged: (value) => {settings.displayUnitsDist = value ?? DisplayUnitsDist.imperial},
        //             value: settings.displayUnitsDist,
        //             items: const [
        //               DropdownMenuItem(value: DisplayUnitsDist.imperial, child: Text("Imperial")),
        //               DropdownMenuItem(value: DisplayUnitsDist.metric, child: Text("Metric")),
        //             ]),
        //         leading: const Icon(Icons.architecture),
        //       ),
        //       SettingsTile.navigation(
        //         title: const Text("Speed"),
        //         trailing: DropdownButton<DisplayUnitsSpeed>(
        //             onChanged: (value) => {settings.displayUnitsSpeed = value ?? DisplayUnitsSpeed.mph},
        //             value: settings.displayUnitsSpeed,
        //             items: const [
        //               DropdownMenuItem(value: DisplayUnitsSpeed.mph, child: Text("mph")),
        //               DropdownMenuItem(value: DisplayUnitsSpeed.kph, child: Text("kph")),
        //               DropdownMenuItem(value: DisplayUnitsSpeed.kts, child: Text("kts")),
        //               DropdownMenuItem(value: DisplayUnitsSpeed.mps, child: Text("m/s")),
        //             ]),
        //         leading: const Icon(Icons.timer),
        //       ),
        //       SettingsTile.navigation(
        //         title: const Text("Vario"),
        //         trailing: DropdownButton<DisplayUnitsVario>(
        //             onChanged: (value) => {settings.displayUnitsVario = value ?? DisplayUnitsVario.fpm},
        //             value: settings.displayUnitsVario,
        //             items: const [
        // DropdownMenuItem(value: DisplayUnitsVario.fpm, child: Text("ft/m")),
        // DropdownMenuItem(value: DisplayUnitsVario.mps, child: Text("m/s")),
        //             ]),
        //         leading: const Icon(Icons.trending_up),
        //       ),
        //     ]),

        //     // --- General Options
        //     SettingsSection(
        //       title: const Text("General"),
        //       tiles: [
        //         SettingsTile.switchTile(
        //           initialValue: settings.autoStartStopFlight,
        //           onToggle: (value) => settings.autoStartStopFlight = value,
        //           title: const Text("Auto Start/Stop Flight"),
        //           leading: const Icon(Icons.play_arrow),
        //         ),
        //         SettingsTile.switchTile(
        //           initialValue: settingsMgr.groundMode.value,
        //           onToggle: (value) => settingsMgr.groundMode.value = value,
        //           title: const Text("Ground Support Mode"),
        //           leading: const Icon(Icons.directions_car),
        //           // description:
        //           //     const Text("Alters UI and doesn't record track."),
        //         ),
        //       ],
        //     ),

        //     // --- UI options
        //     SettingsSection(
        //       title: const Text("UI Options"),
        //       tiles: [
        //         SettingsTile.switchTile(
        //           initialValue: settings.mapControlsRightSide,
        //           onToggle: (value) => settings.mapControlsRightSide = value,
        //           title: const Text("Right-handed UI"),
        //           leading: const Icon(Icons.swap_horiz),
        //           // description: const Text(
        //           //     "Move map control buttons to the right side."),
        //         ),
        //         SettingsTile.switchTile(
        //           initialValue: settings.showPilotNames,
        //           onToggle: (value) => settings.showPilotNames = value,
        //           title: const Text("Always Show Pilot Names"),
        //           leading: const Icon(Icons.abc),
        //           // description: const Text(
        //           //     "Move map control buttons to the right side."),
        //         ),
        //         SettingsTile.navigation(
        //             title: const Text("Primary Altimeter"),
        //             leading: const Icon(Icons.vertical_align_top),
        //             trailing: DropdownButton<String>(
        //                 onChanged: (value) => {settings.altInstr = value ?? "MSL"},
        //                 value: settings.altInstr,
        //                 items: const [
        //                   DropdownMenuItem(value: "AGL", child: Text("AGL")),
        //                   DropdownMenuItem(value: "MSL", child: Text("MSL")),
        //                 ])),
        //         if (localeZone == "NA")
        //           SettingsTile.switchTile(
        //             title: const Text("Hide Weather Overlay"),
        //             leading: const Icon(Icons.cloud),
        //             onToggle: (value) => {settings.showWeatherOverlay = !value},
        //             initialValue: !settings.showWeatherOverlay,
        //           ),
        //         SettingsTile.switchTile(
        //           title: const Text("Hide Airspace Overlay"),
        //           leading: SvgPicture.asset(
        //             "assets/images/airspace.svg",
        //             color: Colors.grey.shade400,
        //           ),
        //           onToggle: (value) => {settings.showAirspaceOverlay = !value},
        //           initialValue: !settings.showAirspaceOverlay,
        //         )
        //       ],
        //     ),
        //     // --- ADSB options
        //     SettingsSection(title: const Text("ADSB"), tiles: [
        //       SettingsTile.navigation(
        //         title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        //           const Text("Proximity Profile"),
        //           // const Divider(),
        //           Text(
        //             settings.proximityProfile.toMultilineString(settings),
        //             style: const TextStyle(fontSize: 12, color: Colors.white60),
        //           )
        //         ]),
        //         leading: const Icon(Icons.radar),
        //         trailing: DropdownButton<String>(
        //           onChanged: (value) {
        //             settings.selectProximityConfig(value ?? "Medium");
        //           },
        //           value: settings.proximityProfileName,
        //           items: settings.proximityProfileOptions.entries
        //               .map((each) => DropdownMenuItem(value: each.key, child: Text(each.key)))
        //               .toList(),
        //         ),
        //       ),
        //       // --- Test Audio
        //       SettingsTile.navigation(
        //         title: const Text("Test Warning Audio"),
        //         // leading: const Icon(Icons.volume_up),
        //         onPressed: (event) => {Provider.of<ADSB>(context, listen: false).testWarning()},
        //         trailing: const Icon(Icons.volume_up),
        //       ),
        //     ]),

        //     /// --- Patreon Info
        //     SettingsSection(
        //         title: Row(
        //           mainAxisSize: MainAxisSize.min,
        //           children: [
        //             const Text("Patreon Identity"),
        //             IconButton(
        //                 onPressed: () => {showPatreonInfoDialog(context)},
        //                 padding: EdgeInsets.zero,
        //                 visualDensity: VisualDensity.compact,
        //                 iconSize: 20,
        //                 icon: const Icon(
        //                   Icons.help,
        //                   size: 20,
        //                   color: Colors.lightBlue,
        //                 ))
        //           ],
        //         ),
        //         tiles: [
        //           SettingsTile.navigation(
        //             title: TextFormField(
        //                 initialValue: settings.patreonName,
        //                 decoration: const InputDecoration(label: Text("First Name")),
        //                 onChanged: (value) {
        //                   settings.patreonName = value;
        //                 }),
        //             trailing: Container(),
        //           ),
        //           SettingsTile.navigation(
        //             title: Form(
        //               key: emailFormKey,
        //               child: TextFormField(
        //                 initialValue: settings.patreonEmail,
        //                 validator: (value) =>
        //                     EmailValidator.validate(value ?? "") || value == "" ? null : "Not a valid email",
        //                 decoration: const InputDecoration(label: Text("Email")),
        //                 onChanged: (value) {
        //                   if (emailFormKey.currentState?.validate() ?? false) {
        //                     settings.patreonEmail = value;
        //                   }
        //                 },
        //               ),
        //             ),
        //             trailing: Container(),
        //           ),
        //         ]),

        //     // --- Map Cache
        //     SettingsSection(title: const Text("Map Cache"), tiles: <SettingsTile>[
        //       SettingsTile.navigation(
        //         title: FutureBuilder<String>(
        //             future: settings.getMapTileCacheSize(),
        //             initialData: "?",
        //             builder: (context, value) {
        //               return Text("Empty Cache  ( ${value.data} )");
        //             }),
        //         trailing: const Icon(Icons.delete, color: Colors.red),
        //         onPressed: (_) {
        //           setState(() {
        //             settings.emptyMapTileCache();
        //             // settings.purgeMapTileCache();
        //           });
        //         },
        //       )
        //     ]),

        //     // --- Debug Tools
        //     SettingsSection(
        //         title: const Text(
        //           "Debug Tools",
        //           style: TextStyle(color: Colors.red),
        //         ),
        //         tiles: <SettingsTile>[
        //           // --- Toggle: Location Spoofing
        //           SettingsTile.switchTile(
        //             initialValue: settings.spoofLocation,
        //             title: const Text("Spoof Location"),
        //             leading: const Icon(
        //               Icons.location_off,
        //               color: Colors.red,
        //             ),
        //             onToggle: (value) => {settings.spoofLocation = value},
        //           ),
        //           // // --- Clear path
        //           // SettingsTile.navigation(
        //           //   title: const Text("Clear Current Flight"),
        //           //   leading: const Icon(
        //           //     Icons.delete_sweep,
        //           //     color: Colors.red,
        //           //   ),
        //           //   onPressed: (_) {
        //           //     Provider.of<MyTelemetry>(context, listen: false).recordGeo.clear();
        //           //     Provider.of<MyTelemetry>(context, listen: false).flightTrace.clear();
        //           //   },
        //           // ),
        //           // --- Erase Identity
        //           SettingsTile.navigation(
        //             title: const Text("Clear Identity"),
        //             // description: const Text(
        //             //     "This will reset your pilot ID and profile!"),
        //             leading: const Icon(
        //               Icons.badge,
        //               color: Colors.red,
        //             ),
        //             onPressed: (value) => {
        //               showDialog(
        //                   context: context,
        //                   builder: (BuildContext ctx) {
        //                     return AlertDialog(
        //                       title: const Text('Please Confirm'),
        //                       content: const Text('Are you sure you want to clear your Identity?'),
        //                       actions: [
        //                         // The "Yes" button
        //                         TextButton.icon(
        //                             onPressed: () {
        //                               // Clear Profile
        //                               Provider.of<Profile>(context, listen: false).eraseIdentity();

        //                               // Remove Avatar saved file
        //                               path_provider.getTemporaryDirectory().then((tempDir) {
        //                                 var outfile = File("${tempDir.path}/avatar.jpg");
        //                                 outfile.exists().then((value) => {if (value) outfile.delete()});
        //                               });

        //                               // Close the dialog
        //                               Navigator.of(context).pop();
        //                             },
        //                             icon: const Icon(
        //                               Icons.delete_forever,
        //                               color: Colors.red,
        //                             ),
        //                             label: const Text('Yes')),
        //                         TextButton(
        //                             onPressed: () {
        //                               // Close the dialog
        //                               Navigator.of(context).pop();
        //                             },
        //                             child: const Text('No'))
        //                       ],
        //                     );
        //                   }),
        //             },
        //           ),
        //           // --- Erase all cached avatars
        //           SettingsTile.navigation(
        //             title: const Text("Clear cached avatars"),
        //             leading: const Icon(
        //               Icons.account_circle,
        //               color: Colors.red,
        //             ),
        //             onPressed: (value) => {
        //               showDialog(
        //                   context: context,
        //                   builder: (BuildContext ctx) {
        //                     return AlertDialog(
        //                       title: const Text('Please Confirm'),
        //                       content: const Text('Are you sure you want to clear all cached avatars?'),
        //                       actions: [
        //                         // The "Yes" button
        //                         TextButton.icon(
        //                             onPressed: () {
        //                               // // Clear Profile
        //                               // Provider.of<Profile>(context, listen: false).eraseIdentity();

        //                               // // Remove Avatar saved file
        //                               // path_provider.getTemporaryDirectory().then((tempDir) {
        //                               //   var outfile = File(tempDir.path + "/avatar.jpg");
        //                               //   outfile.exists().then((value) => {if (value) outfile.delete()});
        //                               // });
        //                               path_provider.getTemporaryDirectory().then((tempDir) {
        //                                 var fileAvatar = Directory("${tempDir.path}/avatars/");
        //                                 fileAvatar.delete(recursive: true);
        //                               });

        //                               // Close the dialog
        //                               Navigator.of(context).pop();
        //                             },
        //                             icon: const Icon(
        //                               Icons.delete_forever,
        //                               color: Colors.red,
        //                             ),
        //                             label: const Text('Yes')),
        //                         TextButton(
        //                             onPressed: () {
        //                               // Close the dialog
        //                               Navigator.of(context).pop();
        //                             },
        //                             child: const Text('No'))
        //                       ],
        //                     );
        //                   }),
        //             },
        //           ),
        //         ]),
        //   ],
        // )
        );
  }
}
