
import 'package:flutter/material.dart';

class TopInstrument extends StatelessWidget {
  const TopInstrument({Key? key, required this.value}) : super(key: key);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(value);
  } 
}

