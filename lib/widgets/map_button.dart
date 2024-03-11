import 'dart:ui';

import 'package:flutter/material.dart';

class MapButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onPressed;
  final double size;
  final bool selected;

  const MapButton(
      {required this.child, required this.size, required this.onPressed, required this.selected, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(30)),
        child: MaterialButton(
            visualDensity: VisualDensity.compact,
            onPressed: onPressed,
            elevation: 0,
            color: Colors.white12,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(30)),
              side: BorderSide(color: selected ? Colors.black : Colors.black45, width: selected ? 3 : 1),
            ),
            child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1), child: child)),
      ),
    );
  }
}
