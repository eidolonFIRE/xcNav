import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

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
    required this.onToggleOptional,
    required this.isSelected,
    this.onDoubleTap,
    this.showPilots = true,
  }) : super(key: key);

  final Waypoint waypoint;
  final int index;
  final bool isSelected;
  final bool showPilots;

  // callbacks
  final VoidCallback onSelect;
  final VoidCallback onToggleOptional;
  final VoidCallback? onDoubleTap;

  @override
  State<WaypointCard> createState() => _WaypointCardState();
}

class _WaypointCardState extends State<WaypointCard> {
  DateTime? _lastSelect;

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isSelected
        ? Colors.black
        : (widget.waypoint.isOptional ? Colors.grey.shade600 : Colors.white);
    return Container(
      color: widget.isSelected ? Colors.grey.shade200 : Colors.grey.shade900,
      key: ValueKey(widget.waypoint),
      margin: const EdgeInsets.all(0),
      constraints: const BoxConstraints(maxHeight: 100),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Column(
            children: [
              Expanded(
                child: SizedBox(
                    width: 4,
                    child: Container(color: widget.waypoint.getColor())),
              ),
              GestureDetector(
                onTap: widget.onToggleOptional,
                child: SizedBox(
                  width: 40,
                  child: Stack(
                    alignment: AlignmentDirectional.center,
                    clipBehavior: Clip.none,
                    children: [
                      SvgPicture.asset(
                        "assets/images/wp${widget.waypoint.latlng.length > 1 ? "_path" : ""}${widget.waypoint.isOptional ? "_optional" : ""}.svg",
                        height: 56,
                        color: widget.waypoint.getColor(),
                      ),
                      // if (waypoint.isOptional)
                      //   SvgPicture.asset(
                      //     "assets/images/wp_strike.svg",
                      //     height: 56,
                      //     color: Colors.red.withAlpha(140),
                      //   )
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                    width: 4,
                    child: Container(color: widget.waypoint.getColor())),
              ),
            ],
          ),
          Expanded(
            child: Flex(
              direction: Axis.horizontal,
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      final delta = _lastSelect != null
                          ? DateTime.now().difference(_lastSelect!)
                          : null;
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
                          if (widget.waypoint.icon != null)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: getWpIcon(
                                widget.waypoint.icon,
                                24,
                                textColor,
                              ),
                            ),
                          if (widget.waypoint.icon != null)
                            const TextSpan(text: " "),
                          // --- Name
                          TextSpan(
                              text: widget.waypoint.name,
                              style: TextStyle(color: textColor, fontSize: 24)),
                          // --- Length
                          if (widget.waypoint.latlng.length > 1)
                            TextSpan(
                                text: " (",
                                style: TextStyle(
                                    color: textColor.withAlpha(150),
                                    fontSize: 18)),
                          if (widget.waypoint.latlng.length > 1)
                            richValue(
                                UnitType.distCoarse, widget.waypoint.length,
                                digits: 3,
                                decimals: 1,
                                valueStyle: TextStyle(
                                    color: textColor.withAlpha(150),
                                    fontSize: 18),
                                unitStyle: TextStyle(
                                    color: textColor.withAlpha(150),
                                    fontSize: 12)),

                          if (widget.waypoint.latlng.length > 1)
                            TextSpan(
                                text: ")",
                                style: TextStyle(
                                    color: textColor.withAlpha(150),
                                    fontSize: 18)),
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
                    var pilots = group.pilots.values.where(
                        (element) => element.selectedWaypoint == widget.index);

                    if (pilots.isEmpty) return Container();

                    final width = min(MediaQuery.of(context).size.width / 3,
                            pilots.length * 48 / pow(pilots.length, 0.3))
                        .toDouble();
                    return SizedBox(
                      width: width,
                      height: 48,
                      child: Stack(
                        children: pilots
                            .map((e) => AvatarRound(e.avatar, 24))
                            .mapIndexed(
                              (index, element) => Positioned(
                                left: (width - 48) /
                                    max(1, pilots.length - 1) *
                                    index,
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
