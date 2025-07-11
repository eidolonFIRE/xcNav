import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/models/gear.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

Future<Gear?> editGear(BuildContext context, {Gear? gear}) {
  gear ??= Gear();

  return showDialog<Gear>(
      context: context,
      builder: (context) {
        final formKey = GlobalKey<FormState>();

        final controllerWingMM = TextEditingController(text: gear?.wingMakeModel);
        final controllerWingSize = TextEditingController(text: gear?.wingSize);
        final controllerMotorMM = TextEditingController(text: gear?.frameMakeModel);
        final controllerEngine = TextEditingController(text: gear?.engine);
        final controllerProp = TextEditingController(text: gear?.prop);
        final controllerTank =
            TextEditingController(text: gear?.tankSize == null ? null : printDoubleSimple(gear!.tankSize!));
        final controllerBladder =
            TextEditingController(text: gear?.bladderSize == null ? null : printDoubleSimple(gear!.bladderSize!));
        final controllerOther = TextEditingController(text: gear?.other);
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text("gear.Wing".tr(), style: TextStyle(color: Colors.lightBlue)),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: controllerWingMM,
                              decoration: InputDecoration(
                                  hintText: "gear.make_model".tr(),
                                  floatingLabelBehavior: FloatingLabelBehavior.always),
                              onChanged: (value) => gear?.wingMakeModel = value,
                            ),
                          ),
                          SizedBox(
                            width: 30,
                            child: TextFormField(
                              controller: controllerWingSize,
                              textAlign: TextAlign.center,
                              inputFormatters: [LengthLimitingTextInputFormatter(2)],
                              decoration: InputDecoration(
                                hintText: "gear.Size".tr(),
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
                                                label: Text("btn.Select".tr()))
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "gear.Motor".tr(),
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
                              controller: controllerMotorMM,
                              decoration: InputDecoration(
                                  hintText: "gear.make_model".tr(),
                                  floatingLabelBehavior: FloatingLabelBehavior.always),
                              onChanged: (value) => gear?.frameMakeModel = value,
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: controllerEngine,
                              decoration: InputDecoration(hintText: "gear.Engine".tr()),
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
                            flex: 1,
                            child: TextFormField(
                              controller: controllerProp,
                              decoration: InputDecoration(
                                  hintText: "gear.Propeller".tr(), floatingLabelBehavior: FloatingLabelBehavior.always),
                              onChanged: (value) => gear?.prop = value,
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: controllerTank,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.end,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]"))],
                              decoration: InputDecoration(
                                  hintText: "gear.Tank".tr(),
                                  suffixText: getUnitStr(UnitType.fuel),
                                  contentPadding: const EdgeInsets.only(right: 10)),
                              onChanged: (value) => gear?.tankSize = parseAsDouble(value),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: controllerBladder,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.end,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]"))],
                              decoration: InputDecoration(
                                  hintText: "gear.Bladder".tr(),
                                  suffixText: getUnitStr(UnitType.fuel),
                                  prefixText: "+",
                                  contentPadding: const EdgeInsets.only(right: 10)),
                              onChanged: (value) => gear?.bladderSize = parseAsDouble(value),
                            ),
                          ),
                        ],
                      ),

                      Container(
                        height: 24,
                      ),

                      // OTHER
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text("gear.other_details".tr(), style: TextStyle(color: Colors.lightBlue)),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: TextFormField(
                          controller: controllerOther,
                          decoration: InputDecoration(
                              hintText: "gear.other_details_example".tr(),
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
                      debugPrint("${"btn.Saving".tr()}: ${jsonEncode(gear?.toJson())}");
                      SharedPreferences.getInstance()
                          .then((prefs) => prefs.setString("gear_last_saved_value", jsonEncode(gear?.toJson())));
                    }
                    Navigator.pop(context, gear);
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
