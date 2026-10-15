import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:xcnav/models/airspace.dart';

/// List the airspaces at a tapped point, lowest first.
void showAirspaceInfoDialog(BuildContext context, List<Airspace> airspaces) {
  final sorted = airspaces.toList()..sort((a, b) => a.lower.meters.compareTo(b.lower.meters));
  showDialog(
      context: context,
      builder: (context) => AlertDialog(
            title: Text("Airspace".tr()),
            content: SizedBox(
              width: MediaQuery.of(context).size.width - 40,
              child: ListView(
                  shrinkWrap: true,
                  children: sorted
                      .map((e) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                                width: 8,
                                height: 40,
                                decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(4))),
                            title: Text(e.name),
                            subtitle: Text(e.label),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [Text(e.upper.toString()), Text(e.lower.toString())],
                            ),
                          ))
                      .toList()),
            ),
          ));
}
