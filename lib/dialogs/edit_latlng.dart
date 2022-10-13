import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

Future<LatLng?> editLatLng(BuildContext context, {LatLng? latlng}) {
  // newWaypointName.value = TextEditingValue(text: waypoint.name);
  var formKey = GlobalKey<FormState>();
  final reMatch = RegExp(r"([-\d]+.?[\d]*),[\s]*([-\d]+.?[\d]*)");
  final TextEditingController latlngText = TextEditingController();

  return showDialog<LatLng?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text(
              "Waypoint from Coordinates",
              style: Theme.of(context).textTheme.titleSmall,
            ),
            titlePadding: const EdgeInsets.all(10),
            contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Edit Name
                Form(
                  key: formKey,
                  child: TextFormField(
                    initialValue: latlng?.toString(),
                    controller: latlngText,
                    autofocus: true,
                    validator: (value) {
                      if (value != null) {
                        if (value.trim().isEmpty) return "Must not be empty";
                        if (!reMatch.hasMatch(value))
                          return "Unrecognized Format";
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      hintText: "Lat, Long  (or google-maps url)",
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const Divider(
                  height: 20,
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                  label: const Text("Cancel"),
                  onPressed: () => {Navigator.pop(context, null)},
                  icon: const Icon(
                    Icons.cancel,
                    size: 20,
                    color: Colors.red,
                  )),
              TextButton.icon(
                  label: const Text("Ok"),
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      final latLngValues = reMatch.firstMatch(latlngText.text);

                      if (latLngValues != null) {
                        Navigator.pop(
                            context,
                            LatLng(double.parse(latLngValues.group(1)!),
                                double.parse(latLngValues.group(2)!)));
                      } else {
                        Navigator.pop(context);
                      }
                    }
                  },
                  icon: const Icon(
                    Icons.check,
                    size: 20,
                    color: Colors.lightGreen,
                  )),
            ],
          );
        });
      });
}
