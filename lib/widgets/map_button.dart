import 'package:flutter/material.dart';

class MapButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onPressed;
  final double size;
  final bool selected;

  const MapButton(
      {required this.child,
      required this.size,
      required this.onPressed,
      required this.selected,
      Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: MaterialButton(
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(30)),
            side: BorderSide(color: Colors.black, width: selected ? 3 : 1),
          ),
          child: child),
    );
  }
}
