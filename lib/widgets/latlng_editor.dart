import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class LatLngEditor extends StatelessWidget {
  static final reMatch = RegExp(r"([-\d]+\.?[\d]*),[\s]*([-\d]+\.?[\d]*)");
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
      onLatLngs(LatLngEditor.reMatch
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
          maxLines: 1,
          onChanged: tryUpdate,
          onSaved: tryUpdate,
          controller: controller,
          // autofocus: true,
          validator: (value) {
            if (value != null) {
              if (value.trim().isEmpty) return "Must not be empty";
              if (!reMatch.hasMatch(value)) return "Unrecognized Format";
            }
            return null;
          },
          decoration: const InputDecoration(
            hintText: "Lat, Long  (or google-maps url)",
            // border: OutlineInputBorder(),
          ),
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.bottom,
          style: const TextStyle(fontSize: 16),
        ));
  }
}
