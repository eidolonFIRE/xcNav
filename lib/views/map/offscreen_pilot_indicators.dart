import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/providers/group.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/pilot_marker.dart';

/// Arrows around the edge of the map pointing toward group pilots that are out of view.
class OffscreenPilotIndicators extends StatelessWidget {
  final MapController mapController;
  final bool Function(LatLng point) isInView;

  const OffscreenPilotIndicators({super.key, required this.mapController, required this.isInView});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: mapController.mapEventStream,
        builder: (context, mapEvent) => SizedBox(
              width: min(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
              height: min(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
              child: Stack(
                  alignment: Alignment.center,
                  children: Provider.of<Group>(context)
                      .activePilots
                      .where((e) => !isInView(e.geo!.latlng))
                      .map((e) => Builder(builder: (context) {
                            final theta = (latlngCalc.bearing(mapController.camera.center, e.geo!.latlng) +
                                    mapController.camera.rotation -
                                    90) *
                                pi /
                                180;
                            final hypo = MediaQuery.of(context).size.width * 0.8 - 40;
                            final dist = latlngCalc.distance(mapController.camera.center, e.geo!.latlng);

                            return Opacity(
                                opacity: 0.5,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    max(0, cos(theta) * hypo),
                                    max(0, sin(theta) * hypo),
                                    max(0, cos(theta) * -hypo),
                                    max(0, sin(theta) * -hypo),
                                  ),
                                  child: Stack(
                                    children: [
                                      Container(
                                          transformAlignment: const Alignment(0, 0),
                                          transform: Matrix4.translationValues(cos(theta) * 30, sin(theta) * 30, 0)
                                            ..rotateZ(theta),
                                          child: const Icon(
                                            Icons.east,
                                            color: Colors.black,
                                            size: 40,
                                          )),
                                      Container(
                                        transformAlignment: const Alignment(0, 0),
                                        child: PilotMarker(
                                          e,
                                          20,
                                        ),
                                      ),
                                      Container(
                                          width: 40,
                                          transform: Matrix4.translationValues(0, 40, 0),
                                          child: Text.rich(
                                            richValue(UnitType.distCoarse, dist,
                                                digits: 4,
                                                decimals: 1,
                                                valueStyle: const TextStyle(color: Colors.black, fontSize: 18),
                                                unitStyle: const TextStyle(color: Colors.black87, fontSize: 14)),
                                            softWrap: false,
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.visible,
                                          ))
                                    ],
                                  ),
                                ));
                          }))
                      .toList()),
            ));
  }
}
