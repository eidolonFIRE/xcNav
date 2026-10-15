import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:xcnav/models/airport_info.dart';
import 'package:xcnav/units.dart';

/// Airport name, elevation, and radio frequencies. Optionally add it as a waypoint.
void showAirportInfoDialog(BuildContext context, AirportInfo airport, {required void Function() onAddWaypoint}) {
  showDialog(
      context: context,
      builder: (context) => AlertDialog(
            title: Text.rich(TextSpan(children: [
              TextSpan(text: airport.name),
              if (airport.code != null)
                TextSpan(text: "  ${airport.code}", style: const TextStyle(color: Colors.grey, fontSize: 18)),
            ])),
            content: SizedBox(
              width: MediaQuery.of(context).size.width - 40,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Elevation / private
                  Text.rich(TextSpan(children: [
                    if (airport.elevation != null) ...[
                      const WidgetSpan(child: Icon(Icons.terrain, size: 20, color: Colors.grey)),
                      const TextSpan(text: " "),
                      richValue(UnitType.distFine, airport.elevation!, unitStyle: const TextStyle(color: Colors.grey)),
                    ],
                    if (airport.private)
                      TextSpan(text: "    ${"Private".tr()}", style: const TextStyle(color: Colors.amber)),
                  ])),
                  const Divider(),

                  // --- Frequencies
                  if (airport.frequencies.isEmpty)
                    Text("No radio frequencies listed".tr(), style: const TextStyle(color: Colors.grey)),
                  if (airport.frequencies.isNotEmpty)
                    Flexible(
                      child: ListView(
                          shrinkWrap: true,
                          children: airport.frequencies
                              .map((e) => ListTile(
                                    key: ValueKey("airportFreq_${e.value}_${e.type}"),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Text(e.value,
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: e.isLocal ? FontWeight.bold : FontWeight.normal,
                                            fontFeatures: const [FontFeature.tabularFigures()])),
                                    title: Text(e.typeName),
                                    subtitle: e.name.isNotEmpty ? Text(e.name) : null,
                                  ))
                              .toList()),
                    ),
                ],
              ),
            ),
            actions: [
              ElevatedButton.icon(
                  key: const Key("airportInfo_addWaypoint"),
                  label: Text("Waypoint".tr()),
                  onPressed: () {
                    Navigator.pop(context);
                    onAddWaypoint();
                  },
                  icon: const ImageIcon(
                    AssetImage("assets/images/add_waypoint_pin.png"),
                    color: Colors.lightGreen,
                  )),
            ],
          ));
}
