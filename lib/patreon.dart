import 'package:flutter/material.dart';

bool isTierRecognized(String? tier) {
  return tierColors[tier] != null;
}

const Map<String, Color> tierColors = {
  "Swooplander": Colors.blue,
  "Flycamper": Color.fromARGB(255, 0xff, 0x42, 0x4D),
};

Widget tierBadge(String? tier) {
  return Card(
      child: Padding(
    padding: const EdgeInsets.all(4.0),
    child: Row(
      children: [
        Padding(
          padding: const EdgeInsets.all(2.0),
          child: Image.asset(
            "assets/external/Digital-Patreon-Logo_FieryCoral.png",
            height: 14,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: Text(tier ?? "Supporter", style: const TextStyle(color: Colors.amber, fontSize: 12)),
        ),
      ],
    ),
  ));
}
