import 'package:flutter/material.dart';
import 'package:xcnav/ble_devices/ble_device_value.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

/// Edit the [MapValue] calibration curve of a [BleLoggedValue].
///
/// [onSave] is called with the new curve, or null when calibration is cleared.
class EditCalibrationDialog extends StatefulWidget {
  final String title;
  final BleLoggedValue<double> value;
  final void Function(MapValue<double>? calibration) onSave;

  const EditCalibrationDialog({super.key, required this.title, required this.value, required this.onSave});

  @override
  State<EditCalibrationDialog> createState() => _EditCalibrationDialogState();
}

class _EditCalibrationDialogState extends State<EditCalibrationDialog> {
  final List<(TextEditingController, TextEditingController)> rows = [];
  String? errorText;

  @override
  void initState() {
    super.initState();
    for (final point in widget.value.calibration?.points ?? <List<double>>[]) {
      addRow(point[0], point[1]);
    }
  }

  @override
  void dispose() {
    for (final row in rows) {
      row.$1.dispose();
      row.$2.dispose();
    }
    super.dispose();
  }

  void addRow(double? raw, double? actual) {
    rows.add((
      TextEditingController(text: raw == null ? "" : printDoubleSimple(raw, decimals: 3)),
      TextEditingController(text: actual == null ? "" : printDoubleSimple(actual, decimals: 3)),
    ));
  }

  void save() {
    final List<List<double>> points = [];
    for (final row in rows) {
      final raw = parseAsDouble(row.$1.text);
      final actual = parseAsDouble(row.$2.text);
      if (raw == null || actual == null) {
        setState(() => errorText = "All values must be numbers");
        return;
      }
      points.add([raw, actual]);
    }
    final calibration = MapValue.validate(points);
    if (calibration == null) {
      setState(() => errorText = "Need at least 2 points with unique raw values");
      return;
    }
    widget.onSave(calibration);
    Navigator.pop(context);
  }

  Widget numberField(TextEditingController controller) {
    return SizedBox(
      width: 90,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.all(4)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder(
                stream: widget.value.valueRawStream,
                builder: (context, _) => Text(
                    "Raw reading: ${widget.value.lastRawValue == null ? "?" : printDouble(value: widget.value.lastRawValue!, digits: 5, decimals: 1)}")),
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [Text("Raw"), Text("Actual")]),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: rows
                    .map((row) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                            numberField(row.$1),
                            numberField(row.$2),
                            IconButton(
                                onPressed: () => setState(() {
                                      rows.remove(row);
                                      row.$1.dispose();
                                      row.$2.dispose();
                                    }),
                                icon: const Icon(Icons.delete, color: Colors.red)),
                          ]),
                        ))
                    .toList(),
              ),
            ),
            TextButton.icon(
                onPressed: () => setState(() => addRow(widget.value.lastRawValue, null)),
                icon: const Icon(Icons.add),
                label: const Text("Add point")),
            if (errorText != null) Text(errorText!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
            onPressed: () {
              widget.onSave(null);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.clear),
            label: const Text("Clear")),
        ElevatedButton.icon(
            onPressed: save,
            icon: const Icon(Icons.check, color: Colors.green),
            label: const Text("Save")),
      ],
    );
  }
}
