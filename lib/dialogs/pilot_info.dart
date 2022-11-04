import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/map_marker.dart';

void showPilotInfo(BuildContext context, String pilotId) {
  // var group = Provider.of<Group>(context, listen: false);

  const valueStyle = TextStyle(fontSize: 22, color: Colors.white);
  const unitStyle = TextStyle(fontSize: 16, color: Colors.grey);
  const fillStyle = TextStyle(fontSize: 14, color: Colors.grey);

  showDialog(
      context: context,
      barrierLabel: "pilot_info_dialog",
      barrierDismissible: true,
      builder: (context) => Consumer2<MyTelemetry, Group>(builder: (context, myTelemetry, group, child) {
            if (group.pilots[pilotId]?.geo != null) {
              final Pilot pilot = group.pilots[pilotId]!;
              final double dist = pilot.geo!.distanceTo(myTelemetry.geo);

              final double relHdg = latlngCalc.bearing(myTelemetry.geo.latLng, pilot.geo!.latLng) * pi / 180;

              final double closingSpd = myTelemetry.geo.spd * cos(myTelemetry.geo.hdg - relHdg) -
                  pilot.geo!.spd * cos(pilot.geo!.hdg - relHdg);

              final etaIntercept = ETA.fromSpeed(dist, closingSpd);

              Waypoint? selectedWp = Provider.of<ActivePlan>(context, listen: false).waypoints[pilot.selectedWp];
              final ETA? etaWp = selectedWp?.eta(pilot.geo!, pilot.geo!.spd);

              final relAlt = pilot.geo!.alt - myTelemetry.geo.alt;

              const cellHeight = 60.0;

              return AlertDialog(
                insetPadding: EdgeInsets.zero,
                // contentPadding: EdgeInsets.all(10),
                titleTextStyle: const TextStyle(fontSize: 36),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                title: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: Row(
                    // direction: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 15),
                        child: AvatarRound(pilot.avatar, 40),
                      ),
                      Flexible(
                        child: Text(
                          pilot.name,
                          textAlign: TextAlign.start,
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                content: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FixedColumnWidth(40),
                      2: FlexColumnWidth(3),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      /// --- Basic Telemetry
                      TableRow(children: [
                        const TableCell(
                          child: Text(
                            "Telemetry",
                            textAlign: TextAlign.end,
                          ),
                        ),
                        TableCell(
                            child: SizedBox(
                          height: cellHeight,
                          child: VerticalDivider(
                            color: Colors.grey.shade900,
                          ),
                        )),
                        // speed
                        TableCell(
                          child: Text.rich(TextSpan(children: [
                            richValue(UnitType.speed, pilot.geo!.spd,
                                digits: 3, valueStyle: valueStyle, unitStyle: unitStyle),

                            const TextSpan(style: fillStyle, text: ",  "),
                            // alt
                            richValue(UnitType.distFine, pilot.geo!.alt,
                                digits: 5, valueStyle: valueStyle, unitStyle: unitStyle),

                            const TextSpan(style: fillStyle, text: " MSL"),
                          ])),
                        ),
                      ]),

                      /// --- Relative
                      TableRow(children: [
                        const TableCell(
                          child: Text(
                            "Relative Distance",
                            textAlign: TextAlign.end,
                          ),
                        ),
                        TableCell(
                            child: SizedBox(
                          height: cellHeight,
                          child: VerticalDivider(
                            color: Colors.grey.shade900,
                          ),
                        )),
                        TableCell(
                            child: Text.rich(
                          TextSpan(children: [
                            richValue(UnitType.distCoarse, dist,
                                digits: 3, valueStyle: valueStyle, unitStyle: unitStyle),
                            const TextSpan(style: fillStyle, text: ",  "),
                            WidgetSpan(
                              child: Icon(
                                relAlt > 0 ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                color: Colors.white,
                                size: 25,
                              ),
                            ),
                            richValue(UnitType.distFine, relAlt.abs(),
                                digits: 4, valueStyle: valueStyle, unitStyle: unitStyle),
                          ]),
                          softWrap: false,
                        ))
                      ]),

                      /// --- Intercept
                      if (etaIntercept.time != null && etaIntercept.time! < const Duration(hours: 5) && dist > 300)
                        TableRow(children: [
                          const TableCell(
                            child: Text(
                              "Intercept",
                              textAlign: TextAlign.end,
                            ),
                          ),
                          TableCell(
                              child: SizedBox(
                            height: cellHeight,
                            child: VerticalDivider(
                              color: Colors.grey.shade900,
                            ),
                          )),
                          TableCell(
                              child: Text.rich(
                            TextSpan(children: [
                              richHrMin(
                                valueStyle: valueStyle,
                                unitStyle: unitStyle,
                                duration: etaIntercept.time!,
                                longUnits: true,
                              )
                            ]),
                            softWrap: false,
                          ))
                        ]),

                      /// --- Waypoint
                      if (etaWp != null && etaWp.time != null && etaWp.time! < const Duration(hours: 100))
                        TableRow(children: [
                          TableCell(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Card(
                                  margin: EdgeInsets.zero,
                                  color: Colors.grey.shade900,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 5, 10, 8),
                                    child: Text.rich(
                                      TextSpan(children: [
                                        WidgetSpan(
                                          child: Container(
                                            transform: Matrix4.translationValues(0, 2, 0),
                                            child: SizedBox(
                                                width: 26 * 2 / 3, height: 26, child: MapMarker(selectedWp!, 24)),
                                          ),
                                        ),
                                        const TextSpan(text: "  "),
                                        TextSpan(
                                          text: selectedWp.name,
                                          style: valueStyle,
                                        ),
                                      ]),
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                            ),
                          ),
                          TableCell(
                              child: SizedBox(
                            height: cellHeight,
                            child: VerticalDivider(
                              color: Colors.grey.shade900,
                            ),
                          )),
                          TableCell(
                              child: Text.rich(
                            TextSpan(children: [
                              richHrMin(
                                  duration: etaWp.time!, valueStyle: valueStyle, unitStyle: unitStyle, longUnits: true),
                            ]),
                            softWrap: false,
                          ))
                        ]),
                    ]),
              );
            } else {
              // We didn't have telemetry to show for this pilot...
              final Pilot pilot = group.pilots[pilotId]!;
              return AlertDialog(
                  insetPadding: EdgeInsets.zero,
                  // contentPadding: EdgeInsets.all(10),
                  titleTextStyle: const TextStyle(fontSize: 36),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                  title: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.8,
                    child: Row(
                      // direction: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 15),
                          child: AvatarRound(pilot.avatar, 40),
                        ),
                        Flexible(
                          child: Text(
                            pilot.name,
                            textAlign: TextAlign.start,
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  content: const Text("No Telemetry for this pilot!"));
            }
          }));
}
