import 'dart:ui';

import 'package:flutter/material.dart';

class MapButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onPressed;
  final double size;

  const MapButton(
      {required this.child,
      required this.size,
      required this.onPressed,
      Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: MaterialButton(
          onPressed: onPressed,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(30)),
            side: BorderSide(color: Colors.black, width: 1),
          ),
          child: child),
    );
  }
}
