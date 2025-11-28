import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/models/elevation_trigger.dart';
import 'package:xcnav/tts_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/altimeter.dart';

Future<ElevationTrigger?> editElevationTriggerDialog(BuildContext context, {ElevationTrigger? trigger}) {
  bool makingNew = trigger == null;

  return showDialog<ElevationTrigger?>(
      context: context,
      builder: (context) {
        final formkKey = GlobalKey<FormState>(debugLabel: "ElevationTriggerFormKey");
        // Form field controllers
        final editName = TextEditingController(text: trigger?.name);
        final editElevation =
            TextEditingController(text: unitConverters[UnitType.distFine]!(trigger?.elevation ?? 0).round().toString());
        AltimeterMode editAltMode = trigger?.altimeterMode ?? AltimeterMode.msl;
        TriggerDirection editDirection = trigger?.direction ?? TriggerDirection.up;
        final editCalloutRepeats = TextEditingController(text: (trigger?.calloutRepeats ?? 1).toString());
        final editCallout = TextEditingController(text: trigger?.customCallout);

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text("${makingNew ? "New" : "Edit"} Trigger"),
            content: Form(
              key: formkKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Name  "),
                      Expanded(
                        child: TextFormField(
                          validator: nameValidator,
                          keyboardType: TextInputType.name,
                          controller: editName,
                        ),
                      )
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Altitude"),
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          textAlign: TextAlign.end,
                          controller: editElevation,
                          validator: numberValidator,
                          keyboardType: TextInputType.numberWithOptions(decimal: false, signed: true),
                        ),
                      ),
                      SizedBox(
                        width: 55,
                        child: DropdownButton<AltimeterMode>(
                            onChanged: (value) => {
                                  setState(() {
                                    if (value != null) {
                                      editAltMode = value;
                                    }
                                  })
                                },
                            value: editAltMode,
                            items: const [
                              DropdownMenuItem(value: AltimeterMode.agl, child: Text("AGL")),
                              DropdownMenuItem(value: AltimeterMode.msl, child: Text("MSL")),
                            ]),
                      )
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Direction  "),
                      SizedBox(
                        width: 60,
                        child: DropdownButton<TriggerDirection>(
                            onChanged: (value) => {
                                  setState(() {
                                    if (value != null) {
                                      editDirection = value;
                                    }
                                  })
                                },
                            value: editDirection,
                            items: const [
                              DropdownMenuItem(value: TriggerDirection.up, child: Text("Up")),
                              DropdownMenuItem(value: TriggerDirection.down, child: Text("Down")),
                            ]),
                      ),
                      Text("  Callouts"),
                      SizedBox(
                        width: 30,
                        child: TextFormField(
                          textAlign: TextAlign.end,
                          controller: editCalloutRepeats,
                          validator: (value) {
                            final resp = numberValidator(value);
                            if (resp != null) return resp;
                            final number = parseAsDouble(value)?.round() ?? 1;
                            if (number <= 0 || number > 10) {
                              return "1 - 10";
                            }
                            return null;
                          },
                          keyboardType: TextInputType.numberWithOptions(decimal: false, signed: false),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Custom Callout  "),
                      Expanded(
                        child: TextFormField(
                          keyboardType: TextInputType.text,
                          controller: editCallout,
                        ),
                      ),
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            if (editCallout.text.trim().isEmpty) {
                              ttsService.speak(AudioMessage(editElevation.text));
                            } else {
                              ttsService.speak(AudioMessage(editCallout.text));
                            }
                          },
                          icon: Icon(Icons.volume_up)),
                    ],
                  )
                ],
              ),
            ),
            actions: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(
                      context,
                      ElevationTrigger(
                          name: "----{DELETE}----",
                          elevation: 0,
                          altimeterMode: AltimeterMode.agl,
                          direction: TriggerDirection.up));
                },
                icon: const Icon(
                  Icons.delete,
                  color: Colors.red,
                ),
                label: Text("btn.Delete".tr()),
              ),
              ElevatedButton.icon(
                  onPressed: () {
                    if (formkKey.currentState?.validate() ?? false) {
                      Navigator.pop(
                          context,
                          ElevationTrigger(
                              name: editName.text,
                              elevation:
                                  (parseAsDouble(editElevation.text) ?? 0) / unitConverters[UnitType.distFine]!(1),
                              altimeterMode: editAltMode,
                              direction: editDirection,
                              calloutRepeats: parseAsDouble(editCalloutRepeats.text)?.round() ?? 1,
                              customCallout: editCallout.text));
                    } else {
                      // Failed validation
                    }
                  },
                  icon: const Icon(
                    Icons.check,
                    color: Colors.lightGreen,
                  ),
                  label: Text("btn.Save".tr()))
            ],
          );
        });
      });
}

void showElevationTriggersDialog(BuildContext context) {
  showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              content: SizedBox(
                width: MediaQuery.of(context).size.width - 40,
                child: Scrollbar(
                  child: ListView(
                      shrinkWrap: true,
                      children: customElevationTriggers
                          .mapIndexed((i, trigger) => ListTile(
                                leading: Checkbox.adaptive(
                                    value: trigger.enabled,
                                    onChanged: (value) {
                                      setState(() {
                                        trigger.enabled = value ?? trigger.enabled;
                                      });
                                    }),
                                title: Text(trigger.name),
                                trailing: IconButton(
                                    onPressed: () {
                                      editElevationTriggerDialog(context, trigger: trigger).then((value) {
                                        if (value != null) {
                                          setState(() {
                                            if (value.name == "----{DELETE}----") {
                                              customElevationTriggers.removeAt(i);
                                            } else {
                                              customElevationTriggers[i] = value;
                                            }
                                            audioCueService.saveElevationTriggers();
                                          });
                                        }
                                      });
                                    },
                                    icon: Icon(Icons.edit)),
                              ))
                          .toList()),
                ),
              ),
              actions: [
                IconButton(
                    onPressed: () {
                      setState(
                        () {
                          editElevationTriggerDialog(context).then((value) {
                            if (value != null) {
                              setState(() => customElevationTriggers.add(value));
                              audioCueService.saveElevationTriggers();
                            }
                          });
                        },
                      );
                    },
                    icon: Icon(
                      Icons.add,
                      color: Colors.lightGreen,
                    ))
              ],
            );
          }));
}
