import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class LatLngEditor extends StatelessWidget {
  static final reMatchAll = RegExp(r"^([\s]*(-?[\d]+\.?[\d]*)[\s]*,[\s]*(-?[\d]+\.?[\d]*);?[\s]*)+$");
  static final reMatchEach = RegExp(r"(-?[\d]+\.?[\d]*)[\s]*,[\s]*(-?[\d]+\.?[\d]*)");
  final TextEditingController controller = TextEditingController();
  final formKeyLatlng = GlobalKey<FormState>();
  final void Function(List<LatLng> latlngs) onLatLngs;

  LatLngEditor({Key? key, required this.onLatLngs, String? initialText, List<LatLng>? initialLatlngs})
      : super(key: key) {
    if (initialText != null) {
      controller.text = initialText;
    } else if (initialLatlngs != null) {
      controller.text =
          initialLatlngs.map((e) => "${e.latitude.toStringAsFixed(5)}, ${e.longitude.toStringAsFixed(5)}").join("; ");
    }
  }

  void tryUpdate(String? value) {
    if ((formKeyLatlng.currentState?.validate() ?? false)) {
      onLatLngs(LatLngEditor.reMatchEach
          .allMatches(controller.text)
          .map((e) => LatLng(double.parse(e.group(1)!), double.parse(e.group(2)!)))
          .toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
        key: formKeyLatlng,
        autovalidateMode: AutovalidateMode.always,
        child: TextFormField(
          key: const Key("textFormField_latlng"),
          maxLines: 1,
          onChanged: tryUpdate,
          onSaved: tryUpdate,
          controller: controller,
          autofocus: true,
          validator: (value) {
            if (value != null) {
              if (value.trim().isEmpty) return "Must not be empty";
              if (!reMatchAll.hasMatch(value)) return "Unrecognized Format";
              // Check the numbers
              for (final each in LatLngEditor.reMatchEach.allMatches(value)) {
                if (double.parse(each.group(1)!).abs() > 90) {
                  return "Latitude must be between -90 and 90";
                }
                if (double.parse(each.group(2)!).abs() > 180) {
                  return "Longitude must be between -180 and 180";
                }
              }
            }
            return null;
          },
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9.\s\-,;]"))],
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            hintText: "Lat, Long",
            // border: OutlineInputBorder(),
          ),
          textAlign: TextAlign.center,
          // textAlignVertical: TextAlignVertical.bottom,
          style: const TextStyle(fontSize: 18),
        ));
  }
}
