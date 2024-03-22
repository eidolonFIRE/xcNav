import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

// Providers
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/providers/adsb.dart';

//
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/altimeter.dart';
import 'package:xcnav/map_service.dart';

class SettingsEditor extends StatefulWidget {
  const SettingsEditor({Key? key}) : super(key: key);

  @override
  State<SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends State<SettingsEditor> {
  final TextEditingController searchInput = TextEditingController();
  final filterText = TextEditingController();

  Map<String, List<SettingMgrItem>> slices = {};

  final catagoryColors = {
    "Experimental": Colors.amber,
    "Debug Tools": Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      slices = settingsMgr.settings;
    }

    // --- Future Builders
    getMapTileCacheSize().then((value) {
      if (mounted) {
        setState(() {
          settingsMgr.clearMapCache.title = "Clear Map Cache ($value)";
        });
      }
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

    settingsMgr.clearAvatarCache.callback = () {
      showDialog(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              title: const Text('Please Confirm'),
              content: const Text('Are you sure you want to clear all cached avatars?'),
              actions: [
                // The "Yes" button
                TextButton.icon(
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
                TextButton(
                    onPressed: () {
                      // Close the dialog
                      Navigator.of(context).pop();
                    },
                    child: const Text('No'))
              ],
            );
          });
    };

    settingsMgr.eraseIdentity.callback = () {
      showDialog(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              title: const Text('Please Confirm'),
              content: const Text('Are you sure you want to clear your Identity?'),
              actions: [
                // The "Yes" button
                TextButton.icon(
                    onPressed: () {
                      // Clear Profile
                      Provider.of<Profile>(context, listen: false).eraseIdentity();

                      // Remove Avatar saved file
                      path_provider.getTemporaryDirectory().then((tempDir) {
                        var outfile = File("${tempDir.path}/avatar.jpg");
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
                TextButton(
                    onPressed: () {
                      // Close the dialog
                      Navigator.of(context).pop();
                    },
                    child: const Text('No'))
              ],
            );
          });
    };

    return Scaffold(
        appBar: AppBar(
          title: const Text("Settings"),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                autofocus: false,
                // focusNode: textFocusNode,
                style: const TextStyle(fontSize: 20),
                controller: filterText,
                decoration: InputDecoration(
                    contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                    hintText: "search"),
                onChanged: (value) {
                  if (mounted) {
                    setState(() {
                      debugPrint("Refresh settings filter.");
                      slices = settingsMgr.settings.map((key, value) => MapEntry(
                          key,
                          value
                              .where((element) =>
                                  filterText.text.isEmpty ||
                                  weightedRatio("${element.catagory.toLowerCase()} ${element.title.toLowerCase()}",
                                          filterText.text.toLowerCase()) >
                                      min(90, filterText.text.length * 15))
                              .toList()));
                    });
                  }
                },
              ),
            ),
            Expanded(
              child: ListView(
                  children: slices
                      .map((key, catagory) => MapEntry(key,
                              // --- Catagory
                              Builder(builder: (context) {
                            final List<Widget> items = catagory
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
                                                  value: value as bool, onChanged: (value) => e.config!.value = value);
                                              break;
                                            case double:
                                              trailing = SizedBox(
                                                width: 80,
                                                child: TextFormField(
                                                    textAlign: TextAlign.center,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    initialValue: printDoubleSimple(value as double, decimals: 2),
                                                    onChanged: (value) => e.config!.value = parseAsDouble(value) ?? 0),
                                              );
                                              break;
                                            case DisplayUnitsDist:
                                              trailing = DropdownButton<DisplayUnitsDist>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: const [
                                                    DropdownMenuItem(
                                                        value: DisplayUnitsDist.imperial, child: Text("Imperial")),
                                                    DropdownMenuItem(
                                                        value: DisplayUnitsDist.metric, child: Text("Metric")),
                                                  ]);
                                              break;
                                            case DisplayUnitsSpeed:
                                              trailing = DropdownButton<DisplayUnitsSpeed>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: const [
                                                    DropdownMenuItem(value: DisplayUnitsSpeed.mph, child: Text("mph")),
                                                    DropdownMenuItem(value: DisplayUnitsSpeed.kph, child: Text("kph")),
                                                    DropdownMenuItem(value: DisplayUnitsSpeed.kts, child: Text("kts")),
                                                    DropdownMenuItem(value: DisplayUnitsSpeed.mps, child: Text("m/s")),
                                                  ]);
                                              break;
                                            case DisplayUnitsVario:
                                              trailing = DropdownButton<DisplayUnitsVario>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: const [
                                                    DropdownMenuItem(value: DisplayUnitsVario.fpm, child: Text("ft/m")),
                                                    DropdownMenuItem(value: DisplayUnitsVario.mps, child: Text("m/s")),
                                                  ]);
                                              break;
                                            case DisplayUnitsFuel:
                                              trailing = DropdownButton<DisplayUnitsFuel>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: const [
                                                    DropdownMenuItem(value: DisplayUnitsFuel.liter, child: Text("L")),
                                                    DropdownMenuItem(value: DisplayUnitsFuel.gal, child: Text("Gal")),
                                                  ]);
                                              break;
                                            case AltimeterMode:
                                              trailing = DropdownButton<AltimeterMode>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: const [
                                                    DropdownMenuItem(value: AltimeterMode.agl, child: Text("AGL")),
                                                    DropdownMenuItem(value: AltimeterMode.msl, child: Text("MSL")),
                                                  ]);
                                              break;
                                            case ProximitySize:
                                              trailing = DropdownButton<ProximitySize>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: ProximitySize.values
                                                      .map((e) => DropdownMenuItem(
                                                          value: e, child: Text(e.toString().split(".").last)))
                                                      .toList());
                                              break;
                                            default:
                                              trailing = Text(
                                                  "${e.config!.id} Unsupported Type ${e.config!.value.runtimeType}");
                                          }
                                          // Build each
                                          return ListTile(
                                            leading: e.config!.icon,
                                            title: Text(e.title),
                                            subtitle: e.config!.subtitle,
                                            trailing: trailing,
                                            textColor: catagoryColors[key],
                                            iconColor: catagoryColors[key],
                                          );
                                        })
                                    // --- Actions
                                    : ListTile(
                                        textColor: catagoryColors[key],
                                        iconColor: catagoryColors[key],
                                        title: Text(e.title),
                                        trailing: IconButton(
                                            icon: e.action!.actionIcon ?? const Icon(Icons.navigate_next),
                                            onPressed: e.action!.callback),
                                      ))
                                .toList();
                            if (items.isEmpty) return Container();

                            return Column(
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
                                    shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(12))),
                                    color: Colors.grey.shade900,
                                    margin: const EdgeInsets.all(8),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: ListTile.divideTiles(context: context, tiles: items).toList())),
                              ],
                            );
                          })))
                      .values
                      .toList()),
            ),
          ],
        ));
  }
}
