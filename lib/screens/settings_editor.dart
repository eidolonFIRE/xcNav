import 'dart:io';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:xcnav/locale.dart';
import 'package:xcnav/providers/my_telemetry.dart';

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
  const SettingsEditor({super.key});

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
          settingsMgr.clearMapCache.description = "${"Total".tr()}: $value";
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
              title: Text('dialog.confirm.please'.tr()),
              content: Text('dialog.confirm.check_clear_avatars'.tr()),
              actions: [
                // The "btn.Yes" button
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
              title: Text('dialog.confirm.please'.tr()),
              content: Text('dialog.confirm.check_clear_identity'.tr()),
              actions: [
                // The "btn.Yes" button
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
                    label: Text('Yes'.tr())),
                TextButton(
                    onPressed: () {
                      // Close the dialog
                      Navigator.of(context).pop();
                    },
                    child: Text('No'.tr()))
              ],
            );
          });
    };

    return Scaffold(
        appBar: AppBar(
          title: Text("Settings".tr()),
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
                    hintText: "Search".tr()),
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
                                          switch (e.config!.value.runtimeType.toString()) {
                                            case "bool":
                                              trailing = Switch.adaptive(
                                                  value: value as bool, onChanged: (value) => e.config!.value = value);
                                              break;
                                            case "double":
                                              trailing = SizedBox(
                                                width: 80,
                                                child: TextFormField(
                                                    textAlign: TextAlign.center,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    initialValue: printDoubleSimple(value as double, decimals: 2),
                                                    onChanged: (value) => e.config!.value = parseAsDouble(value) ?? 0),
                                              );
                                              break;
                                            case "String":
                                              trailing = SizedBox(
                                                width: 80,
                                                child: TextFormField(
                                                    textAlign: TextAlign.center,
                                                    initialValue: value,
                                                    onChanged: (value) => e.config!.value = value),
                                              );
                                              break;
                                            case "List<String>":
                                              trailing = SizedBox(
                                                width: 80,
                                                child: TextFormField(
                                                    textAlign: TextAlign.center,
                                                    initialValue: (value as List<String>).join(", "),
                                                    onChanged: (value) => e.config!.value =
                                                        value.split(",").map((e) => e.trim()).toList()),
                                              );
                                              break;
                                            case "DisplayUnitsDist":
                                              trailing = DropdownButton<DisplayUnitsDist>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: [
                                                    DropdownMenuItem(
                                                        value: DisplayUnitsDist.imperial, child: Text("Imperial".tr())),
                                                    DropdownMenuItem(
                                                        value: DisplayUnitsDist.metric, child: Text("Metric".tr())),
                                                  ]);
                                              break;
                                            case "DisplayUnitsSpeed":
                                              trailing = DropdownButton<DisplayUnitsSpeed>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: DisplayUnitsSpeed.values
                                                      .map((e) => DropdownMenuItem(
                                                          value: e,
                                                          child: Text(
                                                              getUnitStr(UnitType.speed, lexical: false, override: e))))
                                                      .toList());
                                              break;
                                            case "DisplayUnitsVario":
                                              trailing = DropdownButton<DisplayUnitsVario>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: DisplayUnitsVario.values
                                                      .map((e) => DropdownMenuItem(
                                                          value: e,
                                                          child: Text(
                                                              getUnitStr(UnitType.vario, lexical: false, override: e))))
                                                      .toList());
                                              break;
                                            case "DisplayUnitsFuel":
                                              trailing = DropdownButton<DisplayUnitsFuel>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: DisplayUnitsFuel.values
                                                      .map((e) => DropdownMenuItem(
                                                          value: e,
                                                          child: Text(
                                                              getUnitStr(UnitType.fuel, lexical: false, override: e))))
                                                      .toList());
                                              break;
                                            case "AltimeterMode":
                                              trailing = DropdownButton<AltimeterMode>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: const [
                                                    DropdownMenuItem(value: AltimeterMode.agl, child: Text("AGL")),
                                                    DropdownMenuItem(value: AltimeterMode.msl, child: Text("MSL")),
                                                  ]);
                                              break;
                                            case "ProximitySize":
                                              trailing = DropdownButton<ProximitySize>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: ProximitySize.values
                                                      .map((e) => DropdownMenuItem(
                                                          value: e, child: Text(e.toString().split(".").last.tr())))
                                                      .toList());
                                              break;
                                            case "LanguageOverride":
                                              trailing = DropdownButton<LanguageOverride>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: LanguageOverride.values
                                                      .map((e) => DropdownMenuItem(
                                                          value: e, child: Text(languageNames[e] ?? "None")))
                                                      .toList());
                                              break;
                                            case "BarometerSrc":
                                              trailing = DropdownButton<BarometerSrc>(
                                                  onChanged: (value) =>
                                                      {e.config!.value = value ?? e.config!.defaultValue},
                                                  value: e.config!.value,
                                                  items: BarometerSrc.values
                                                      .map((e) => DropdownMenuItem(
                                                          value: e,
                                                          child: Text(barometerSrcString[e] ?? "Unknown").tr()))
                                                      .toList());
                                              break;
                                            default:
                                              trailing = Text(
                                                  "${e.config!.id} Unsupported Type ${e.config!.value.runtimeType}");
                                          }
                                          // Build each
                                          return ListTile(
                                            leading: e.config!.icon,
                                            title: Text("settings.title.${e.title}".tr()),
                                            subtitle:
                                                e.config.runtimeType != Text ? null : (e.config!.subtitle as Text).tr(),
                                            trailing: trailing,
                                            textColor: catagoryColors[key],
                                            iconColor: catagoryColors[key],
                                          );
                                        })
                                    // --- Actions
                                    : ListTile(
                                        textColor: catagoryColors[key],
                                        iconColor: catagoryColors[key],
                                        title: Text("settings.title.${e.title}".tr()),
                                        subtitle: e.description == null
                                            ? null
                                            : Text(
                                                e.description!,
                                                style: TextStyle(fontSize: 12),
                                              ),
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
                                    "settings.group.$key".tr(),
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
