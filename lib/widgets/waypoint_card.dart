import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:xcnav/models/geo.dart';

import 'package:xcnav/providers/group.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/map_marker.dart';

class WaypointCard extends StatefulWidget {
  const WaypointCard({
    Key? key,
    required this.waypoint,
    required this.index,
    required this.onSelect,
    required this.isSelected,
    this.refLatlng,
    this.onDoubleTap,
    this.showPilots = true,
  }) : super(key: key);

  final Waypoint waypoint;
  final int index;
  final bool isSelected;
  final bool showPilots;

  final LatLng? refLatlng;

  // callbacks
  final VoidCallback onSelect;
  final VoidCallback? onDoubleTap;

  @override
  State<WaypointCard> createState() => _WaypointCardState();
}

class _WaypointCardState extends State<WaypointCard> {
  DateTime? _lastSelect;

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isSelected ? Colors.black : Colors.white;
    return Container(
      color: widget.isSelected ? Colors.grey.shade200 : Colors.grey.shade900,
      key: ValueKey(widget.waypoint),
      margin: const EdgeInsets.all(0),
      constraints: const BoxConstraints(maxHeight: 100),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.refLatlng != null)
            Container(
              constraints: const BoxConstraints(minWidth: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.refLatlng != null)
                    Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Text.rich(
                        richValue(
                            UnitType.distCoarse,
                            Geo(lat: widget.refLatlng!.latitude, lng: widget.refLatlng!.longitude, spd: 1)
                                .getIntercept(widget.waypoint.latlngOriented)
                                .dist,
                            digits: 3,
                            valueStyle: TextStyle(color: widget.isSelected ? Colors.black : Colors.white, fontSize: 18),
                            unitStyle: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 12)),
                        textAlign: TextAlign.end,
                      ),
                    ),
                ],
              ),
            ),
          if (widget.refLatlng != null)
            const VerticalDivider(
              width: 4,
              thickness: 2,
            ),
          Expanded(
            child: Flex(
              direction: Axis.horizontal,
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      final delta = _lastSelect != null ? DateTime.now().difference(_lastSelect!) : null;
                      if (delta == null || delta.inMilliseconds > 300) {
                        widget.onSelect();
                      } else if (delta.inMilliseconds < 300) {
                        widget.onDoubleTap?.call();
                      }

                      _lastSelect = DateTime.now();
                    },
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(children: [
                          // --- Icon
                          if (widget.waypoint.icon != null || widget.waypoint.isPath)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: widget.waypoint.isPath
                                  ? SvgPicture.asset(
                                      "assets/images/path.svg",
                                      color: widget.waypoint.getColor(),
                                      width: 30,
                                    )
                                  : getWpIcon(
                                      widget.waypoint.icon,
                                      24,
                                      widget.waypoint.getColor(),
                                    ),
                            ),
                          if (widget.waypoint.icon != null) const TextSpan(text: " "),
                          // --- Name
                          TextSpan(
                              text: widget.waypoint.name,
                              style: TextStyle(
                                  color: widget.waypoint.ephemeral ? Colors.grey.shade600 : textColor,
                                  fontSize: 24,
                                  fontStyle: widget.waypoint.ephemeral ? FontStyle.italic : FontStyle.normal)),
                          // --- Length
                          if (widget.waypoint.latlng.length > 1)
                            TextSpan(text: " (", style: TextStyle(color: textColor.withAlpha(100), fontSize: 18)),
                          if (widget.waypoint.latlng.length > 1)
                            richValue(UnitType.distCoarse, widget.waypoint.length,
                                digits: 3,
                                decimals: 1,
                                valueStyle: TextStyle(color: textColor.withAlpha(100), fontSize: 18),
                                unitStyle: TextStyle(
                                    color: textColor.withAlpha(100), fontSize: 12, fontStyle: FontStyle.italic)),

                          if (widget.waypoint.latlng.length > 1)
                            TextSpan(text: ")", style: TextStyle(color: textColor.withAlpha(100), fontSize: 18)),
                        ]),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                      ),
                    ),
                  ),
                ),

                /// Pilot Avatars
                if (widget.showPilots)
                  Consumer<Group>(builder: (context, group, child) {
                    var pilots = group.pilots.values.where((element) => element.selectedWp == widget.waypoint.id);

                    if (pilots.isEmpty) return Container();

                    final width =
                        min(MediaQuery.of(context).size.width / 3, pilots.length * 48 / pow(pilots.length, 0.3))
                            .toDouble();
                    return SizedBox(
                      width: width,
                      height: 48,
                      child: Stack(
                        children: pilots
                            .map((e) => AvatarRound(e.avatar, 24))
                            .mapIndexed(
                              (index, element) => Positioned(
                                left: (width - 48) / max(1, pilots.length - 1) * index,
                                child: element,
                              ),
                            )
                            .toList(),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
