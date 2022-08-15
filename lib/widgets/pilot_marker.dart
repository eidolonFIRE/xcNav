import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/dialogs/pilot_info.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/patreon.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/avatar_round.dart';

class PilotMarker extends StatelessWidget {
  final Pilot pilot;
  final double radius;
  final double? hdg;
  final double? relAlt;

  const PilotMarker(this.pilot, this.radius, {Key? key, this.hdg, this.relAlt}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var settings = Provider.of<Settings>(context, listen: false);
    final offsetInfo = (max(0, sin(hdg ?? 0)) * radius / 2 + radius * 2).toDouble();
    return Stack(fit: StackFit.loose, children: [
      // Relative Altitude Indicator

      if (hdg != null)
        Container(
          transformAlignment: const Alignment(0, 0),
          transform: Matrix4.rotationZ(hdg!) * Matrix4.translationValues(0, -12, 0),
          child: SizedBox(
            child: SvgPicture.asset(
              "assets/images/pilot_direction_arrow.svg",
              clipBehavior: Clip.none,
              color: tierColors[pilot.tier],
            ),
          ),
        ),
      GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showPilotInfo(context, pilot.id),
          child: AvatarRound(pilot.avatar, radius, tier: pilot.tier)),

      /// --- Relative Altitude
      if (relAlt != null)
        Container(
            transform: Matrix4.translationValues(offsetInfo, 0, 0),
            // transformAlignment: const Alignment(0, 0),
            child: Text.rich(
              TextSpan(children: [
                WidgetSpan(
                  child: Icon(
                    relAlt! > 0 ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.black,
                    size: 21,
                  ),
                ),
                richValue(UnitType.distFine, relAlt!.abs(),
                    digits: 5,
                    valueStyle: const TextStyle(color: Colors.black),
                    unitStyle: TextStyle(color: Colors.grey.shade700, fontSize: 12))
              ]),
              overflow: TextOverflow.visible,
              softWrap: false,
              maxLines: 1,
              style: const TextStyle(fontSize: 16),
            )),

      /// --- Show name
      if (pilot.avatar == null || settings.showPilotNames)
        Container(
          transform: Matrix4.translationValues(offsetInfo + 5, 18, 0),
          child: Text(
            pilot.name,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            style: const TextStyle(color: Colors.black, fontSize: 22),
          ),
        )
    ]);
  }
}
