import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/models/gear.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

Future<Gear?> editGear(BuildContext context, {Gear? gear}) {
  gear ??= Gear();
  final formKey = GlobalKey<FormState>();
  return showDialog<Gear>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            content: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: Form(
                  key: formKey,
                  child: ListView(
                    shrinkWrap: true,
                    // mainAxisSize: MainAxisSize.min,
                    children: [
                      // WING
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Wing", style: TextStyle(color: Colors.lightBlue)),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: TextEditingController(text: gear?.wingMakeModel),
                              decoration: const InputDecoration(
                                  hintText: "make,  model", floatingLabelBehavior: FloatingLabelBehavior.always),
                              onChanged: (value) => gear?.wingMakeModel = value,
                            ),
                          ),
                          SizedBox(
                            width: 30,
                            child: TextFormField(
                              controller: TextEditingController(text: gear?.wingSize),
                              textAlign: TextAlign.center,
                              inputFormatters: [LengthLimitingTextInputFormatter(2)],
                              decoration: const InputDecoration(
                                hintText: "size",
                                contentPadding: EdgeInsets.all(0),
                              ),
                              onChanged: (value) => gear?.wingSize = value,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              showDialog<Color>(
                                  context: context,
                                  builder: (context) {
                                    HSVColor color = HSVColor.fromColor(Colors.red);
                                    return StatefulBuilder(builder: (context, setState) {
                                      return AlertDialog(
                                          content: SizedBox(
                                            width: MediaQuery.of(context).size.width / 2 + 20,
                                            height: MediaQuery.of(context).size.width / 2 + 20,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                Center(
                                                  child: SizedBox(
                                                      width: 80, height: 80, child: Card(color: color.toColor())),
                                                ),
                                                SizedBox(
                                                    width: MediaQuery.of(context).size.width / 2,
                                                    height: MediaQuery.of(context).size.width / 2,
                                                    child: ColorPickerHueRing(
                                                      color,
                                                      (newColor) {
                                                        setState(
                                                          () => color = newColor,
                                                        );
                                                      },
                                                      strokeWidth: 40,
                                                    )),
                                              ],
                                            ),
                                          ),
                                          actions: [
                                            ElevatedButton.icon(
                                                icon: const Icon(
                                                  Icons.check,
                                                  color: Colors.lightGreen,
                                                ),
                                                onPressed: () {
                                                  Navigator.pop(context, color.toColor());
                                                },
                                                label: const Text("Select"))
                                          ]);
                                    });
                                  }).then((newColor) {
                                setState(() {
                                  gear?.wingColor = newColor;
                                });
                              });
                            },
                            icon: Icon(
                              Icons.color_lens,
                              color: gear?.wingColor,
                              size: 32,
                            ),
                          )
                        ],
                      ),

                      Container(
                        height: 24,
                      ),

                      // MOTOR
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Motor",
                          style: TextStyle(color: Colors.lightBlue),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: TextEditingController(text: gear?.frameMakeModel),
                              decoration: const InputDecoration(
                                  hintText: "make,  model", floatingLabelBehavior: FloatingLabelBehavior.always),
                              onChanged: (value) => gear?.frameMakeModel = value,
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: TextEditingController(text: gear?.engine),
                              decoration: const InputDecoration(hintText: "engine"),
                              onChanged: (value) => gear?.engine = value,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: TextEditingController(text: gear?.prop),
                              decoration: const InputDecoration(
                                  hintText: "prop", floatingLabelBehavior: FloatingLabelBehavior.always),
                              onChanged: (value) => gear?.prop = value,
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: TextEditingController(
                                  text: gear?.tankSize == null ? null : printDoubleSimple(gear!.tankSize!)),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.end,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]"))],
                              decoration: const InputDecoration(
                                  hintText: "tank", suffixText: "L", contentPadding: EdgeInsets.only(right: 10)),
                              onChanged: (value) => gear?.tankSize = parseAsDouble(value),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: TextEditingController(
                                  text: gear?.bladderSize == null ? null : printDoubleSimple(gear!.bladderSize!)),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.end,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]"))],
                              decoration: const InputDecoration(
                                  hintText: "bladder",
                                  suffixText: "L",
                                  prefixText: "+",
                                  contentPadding: EdgeInsets.only(right: 10)),
                              onChanged: (value) => gear?.bladderSize = parseAsDouble(value),
                            ),
                          ),
                        ],
                      ),

                      Container(
                        height: 24,
                      ),

                      // OTHER
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Other Details", style: TextStyle(color: Colors.lightBlue)),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: TextFormField(
                          controller: TextEditingController(text: gear?.other),
                          decoration: const InputDecoration(
                              hintText: "flight box, camping bag, etc...",
                              floatingLabelBehavior: FloatingLabelBehavior.always),
                        ),
                      ),
                    ],
                  )),
            ),
            // actionsOverflowAlignment: OverflowBarAlignment.center,
            // actionsPadding: const EdgeInsets.all(5),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              ElevatedButton.icon(
                  onPressed: () {
                    // Reload last gear saved
                    SharedPreferences.getInstance().then((prefs) {
                      final rawStr = prefs.getString("gear_last_saved_value");
                      if (rawStr?.isNotEmpty ?? false) {
                        gear = Gear.fromJson(jsonDecode(rawStr!));

                        setState(
                          () {
                            formKey.currentState?.reset();
                          },
                        );
                      }
                    });
                  },
                  icon: const Icon(
                    Icons.auto_awesome,
                    color: Colors.blue,
                  ),
                  label: const Text("")),
              ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, Gear());
                  },
                  icon: const Icon(
                    Icons.delete,
                    color: Colors.red,
                  ),
                  label: const Text("")),
              ElevatedButton.icon(
                  onPressed: () {
                    // Save latest to prefs
                    if (gear != null) {
                      SharedPreferences.getInstance()
                          .then((prefs) => prefs.setString("gear_last_saved_value", jsonEncode(gear?.toJson())));
                    }
                    Navigator.pop(context, gear);
                  },
                  icon: const Icon(
                    Icons.check,
                    color: Colors.lightGreen,
                  ),
                  label: const Text("Save"))
            ],
          );
        });
      });
}
