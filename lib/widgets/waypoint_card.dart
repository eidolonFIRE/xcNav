import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

import 'package:xcnav/providers/group.dart';
import 'package:xcnav/models/waypoint.dart';
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
    return Card(
      color: isSelected ? Colors.blue[600] : Colors.grey[800],
      key: ValueKey(waypoint),
      margin: const EdgeInsets.all(1),
      child: ListTile(
        selected: isSelected,
        selectedColor: Colors.black,
        contentPadding: EdgeInsets.zero,
        // visualDensity: VisualDensity.compact,
        leading: GestureDetector(
          onTap: onToggleOptional,
          // padding: EdgeInsets.zero,
          // iconSize: 55,

          child: SizedBox(
            width: 40,
            // height: 60,
            child: Image.asset(
              "assets/images/wp" +
                  (waypoint.latlng.length > 1 ? "_path" : "") +
                  (waypoint.isOptional ? "_optional" : "") +
                  ".png",
              // fit: BoxFit.none,
              height: 55,

              color: Color(waypoint.color ?? Colors.black.value),
            ),
          ),
        ),
        title: Flex(
          direction: Axis.horizontal,
          children: [
            Expanded(
              child: TextButton(
                // style: ButtonStyle(
                //   side: MaterialStateProperty.resolveWith<BorderSide>(
                //       (states) => const BorderSide(color: Colors.black)),
                //   backgroundColor: MaterialStateProperty.resolveWith<Color>(
                //       (states) => Colors.black45),
                //   minimumSize: MaterialStateProperty.resolveWith<Size>(
                //       (states) =>
                //           Size(MediaQuery.of(context).size.width / 4, 40)),
                //   padding:
                //       MaterialStateProperty.resolveWith<EdgeInsetsGeometry>(
                //           (states) => const EdgeInsets.all(12)),
                //   textStyle: MaterialStateProperty.resolveWith<TextStyle>(
                //       (states) =>
                //           const TextStyle(color: Colors.white, fontSize: 24)),
                // ),
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
                            color: isFaded ? Colors.grey[600] : Colors.white,
                          ),
                        ),
                      if (waypoint.icon != null) const TextSpan(text: " "),
                      // --- Name
                      TextSpan(
                        text: waypoint.name,
                        style: TextStyle(
                            color: isFaded ? Colors.grey[600] : Colors.white,
                            fontSize: 24),
                      ),
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
              var pilots = group.pilots.values
                  .where((element) => element.selectedWaypoint == index);

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
                          left:
                              (width - 48) / max(1, pilots.length - 1) * index,
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
