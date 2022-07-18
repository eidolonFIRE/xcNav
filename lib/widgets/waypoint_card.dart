import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

import 'package:xcnav/providers/group.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/map_marker.dart';

class WaypointCard extends StatelessWidget {
  const WaypointCard(
      {Key? key,
      required this.waypoint,
      required this.index,
      required this.onSelect,
      required this.onToggleOptional,
      required this.isSelected,
      required this.isFaded})
      : super(key: key);

  final Waypoint waypoint;
  final int index;
  final bool isSelected;
  final bool isFaded;

  // callbacks
  final VoidCallback onSelect;
  final VoidCallback onToggleOptional;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<Settings>(context, listen: false);
    return Container(
      color: isSelected ? Colors.grey.shade200 : Colors.grey.shade900,
      key: ValueKey(waypoint),
      margin: const EdgeInsets.all(0),
      child: ListTile(
        selected: isSelected,
        selectedColor: Colors.black,
        contentPadding: EdgeInsets.zero,
        leading: GestureDetector(
          onTap: onToggleOptional,
          child: SizedBox(
            width: 40,
            child: Stack(
              alignment: AlignmentDirectional.center,
              clipBehavior: Clip.none,
              children: [
                SvgPicture.asset(
                  "assets/images/wp" +
                      (waypoint.latlng.length > 1 ? "_path" : "") +
                      (waypoint.isOptional ? "_optional" : "") +
                      ".svg",
                  height: 56,
                  color: waypoint.getColor(),
                ),
                if (waypoint.isOptional)
                  SvgPicture.asset(
                    "assets/images/wp_strike.svg",
                    height: 56,
                    color: Colors.red.withAlpha(140),
                  )
              ],
            ),
          ),
        ),
        title: Flex(
          direction: Axis.horizontal,
          children: [
            Expanded(
              child: TextButton(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(children: [
                      // --- Icon
                      if (waypoint.icon != null)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            iconOptions[waypoint.icon],
                            size: 24,
                            color: isSelected ? Colors.black : (isFaded ? Colors.grey.shade600 : Colors.white),
                          ),
                        ),
                      if (waypoint.icon != null) const TextSpan(text: " "),
                      // --- Name
                      TextSpan(
                          text: waypoint.name,
                          style: TextStyle(
                              color: isSelected ? Colors.black : (isFaded ? Colors.grey.shade600 : Colors.white),
                              fontSize: 24)),
                      // --- Length
                      if (waypoint.latlng.length > 1)
                        TextSpan(
                            text: " ( " +
                                printValue(
                                    value: convertDistValueCoarse(settings.displayUnitsDist, waypoint.length),
                                    digits: 3,
                                    decimals: 1),
                            style: const TextStyle(color: Colors.grey, fontSize: 18)),
                      if (waypoint.latlng.length > 1)
                        TextSpan(
                            text: unitStrDistCoarse[settings.displayUnitsDist],
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      if (waypoint.latlng.length > 1)
                        const TextSpan(text: " )", style: TextStyle(color: Colors.grey, fontSize: 18)),
                    ]),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                  ),
                ),
                onPressed: onSelect,
              ),
            ),

            /// Pilot Avatars
            Consumer<Group>(builder: (context, group, child) {
              var pilots = group.pilots.values.where((element) => element.selectedWaypoint == index);

              if (pilots.isEmpty) return Container();

              final width =
                  min(MediaQuery.of(context).size.width / 3, pilots.length * 48 / pow(pilots.length, 0.3)).toDouble();
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

        /// Long-press to sort
        // trailing: ReorderableDragStartListener(
        //   index: index,
        //   child: const Icon(
        //     Icons.drag_handle,
        //     size: 24,
        //   ),
        // ),
      ),
    );
  }
}
