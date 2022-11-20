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
  final double? value;
  final int digits;
  final int decimals;
  final TextStyle valueStyle;
  final TextStyle? unitStyle;
  final String? unitTag;
  final bool isPrimary;

  const Altimeter(this.value,
      {this.digits = 5,
      this.decimals = 0,
      required this.valueStyle,
      this.unitStyle,
      this.unitTag,
      this.isPrimary = true,
      Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return isPrimary
        ? Row(
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            children: [
                value != null
                    ? Text(
                        printDouble(
                            value: unitConverters[UnitType.distFine]!(value!), digits: digits, decimals: decimals),
                        style: valueStyle)
                    : Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SizedBox(
                            width: valueStyle.fontSize != null ? valueStyle.fontSize! / 2 : null,
                            height: valueStyle.fontSize != null ? valueStyle.fontSize! / 2 : null,
                            child: const CircularProgressIndicator()),
                      ),
                Column(
                    verticalDirection: VerticalDirection.up,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(getUnitStr(UnitType.distFine), style: unitStyle),
                      unitTag == null
                          ? Container()
                          : Padding(
                              padding: EdgeInsets.only(bottom: valueStyle.fontSize! - 42),
                              child: AltimeterBadge(unitTag!),
                            ),
                    ])
              ])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 2),
                  child: value != null
                      ? Text(printDouble(value: unitConverters[UnitType.distFine]!(value!), digits: 5, decimals: 0),
                          style: valueStyle)
                      : Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: SizedBox(
                              width: valueStyle.fontSize != null ? valueStyle.fontSize! - 2 : null,
                              height: valueStyle.fontSize != null ? valueStyle.fontSize! - 2 : null,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              )),
                        )),
              unitTag == null ? Container() : AltimeterBadge(unitTag!)
            ],
          );
  }
}
