import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/dialogs/pilot_info.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/units.dart';

class PilotMarker extends StatelessWidget {
  final Pilot pilot;
  final double radius;
  final double? hdg;
  final double? relAlt;

  const PilotMarker(this.pilot, this.radius, {Key? key, this.hdg, this.relAlt}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var settings = Provider.of<Settings>(context, listen: false);
    return Stack(fit: StackFit.loose, children: [
      // Relative Altitude Indicator

      if (hdg != null)
        Container(
          // width: radius * 3,
          // height: radius * 3,
          // color: Colors.amber.withAlpha(100),
          transformAlignment: const Alignment(0, 0),
          transform: Matrix4.rotationZ(hdg!) * Matrix4.translationValues(0, -12, 0),
          child: SizedBox(
            // width: radius * 3,
            // height: radius * 3,
            child: SvgPicture.asset(
              "assets/images/pilot_direction_arrow.svg",
              // fit: BoxFit.none,
              clipBehavior: Clip.none,
              // width: radius,
              // height: radius,
            ),
          ),
        ),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showPilotInfo(context, pilot.id),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: Colors.black,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: ClipOval(
              child: SizedBox(
                  width: radius * 2,
                  height: radius * 2,
                  child: FittedBox(
                      fit: BoxFit.fill, child: pilot.avatar ?? Image.asset("assets/images/default_avatar.png"))),
            ),
          ),
        ),
      ),

      /// --- Relative Altitude
      if (relAlt != null)
        Container(
            transform: Matrix4.translationValues(radius * 2, 0, 0),
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
                TextSpan(
                  text: printValue(
                      value: convertDistValueFine(settings.displayUnitsDist, relAlt!.abs()), digits: 4, decimals: 0),
                  style: const TextStyle(color: Colors.black),
                ),
                TextSpan(
                    text: unitStrDistFine[settings.displayUnitsDist],
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12))
              ]),
              overflow: TextOverflow.visible,
              softWrap: false,
              maxLines: 1,
              style: const TextStyle(fontSize: 16),
            )),

      /// --- Show name
      if (pilot.avatar == null || settings.showPilotNames)
        Container(
          transform: Matrix4.translationValues(radius * 2 + 5, 18, 0),
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
