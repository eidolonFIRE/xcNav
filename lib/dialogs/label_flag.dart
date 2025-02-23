import 'package:flutter/material.dart';

class LabelFlag extends StatelessWidget {
  const LabelFlag({
    super.key,
    required this.direction,
    required this.color,
    required this.text,
  });

  final TextDirection direction;
  final Widget text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final flag = SizedBox(
        height: 40,
        child: VerticalDivider(
          color: color,
          width: 3,
          thickness: 3,
        ));

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (direction == TextDirection.ltr) flag,
        Card(
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(topRight: Radius.circular(10), bottomRight: Radius.circular(10))),
          color: color,
          margin: EdgeInsets.zero,
          child: Padding(padding: const EdgeInsets.all(4.0), child: text),
        ),
        if (direction != TextDirection.ltr) flag,
      ],
    );
  }
}
