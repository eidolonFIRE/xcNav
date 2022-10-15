import 'package:flutter/material.dart';
import 'package:xcnav/units.dart';

class AltimeterBadge extends StatelessWidget {
  final double size;
  final String text;

  const AltimeterBadge(this.text, {this.size = 1.0, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 2),
      color: Colors.white38,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20 * size))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 1) * size,
        child: Text(
          text,
          style: TextStyle(color: Colors.black, fontSize: 10 * size, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class Altimeter extends StatelessWidget {
  final double value;
  final int digits;
  final int decimals;
  final TextStyle? valueStyle;
  final TextStyle? unitStyle;
  final String? unitTag;

  const Altimeter(this.value,
      {this.digits = 5, this.decimals = 0, this.valueStyle, this.unitStyle, this.unitTag, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        children: [
          Text(printDouble(value: unitConverters[UnitType.distFine]!(value), digits: digits, decimals: decimals),
              style: valueStyle),
          Column(
              verticalDirection: VerticalDirection.up,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(getUnitStr(UnitType.distFine), style: unitStyle),
                unitTag == null ? Container() : AltimeterBadge(unitTag!),
              ])
        ]);
  }
}
