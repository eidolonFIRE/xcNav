import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
        leading: IconButton(
          onPressed: onToggleOptional,
          padding: EdgeInsets.zero,
          iconSize: 55,
          icon: Image.asset(
            "assets/images/wp" +
                (waypoint.latlng.length > 1 ? "_path" : "") +
                (waypoint.isOptional ? "_optional" : "") +
                ".png",
            color: Color(waypoint.color ?? Colors.black.value),
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TextButton(
              child: Container(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width / 4,
                    maxWidth: MediaQuery.of(context).size.width / 2,
                  ),
                  child: Text.rich(
                    TextSpan(children: [
                      // --- Icon
                      if (waypoint.icon != null)
                        WidgetSpan(
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
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                  )),
              onPressed: onSelect,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: Provider.of<Group>(context)
                  .pilots
                  .values
                  .where((element) => element.selectedWaypoint == index)
                  .map((e) => AvatarRound(e.avatar, 24))
                  .toList(),
            )
          ],
        ),
        trailing: ReorderableDragStartListener(
          index: index,
          child: const Icon(
            Icons.drag_handle,
            size: 24,
          ),
        ),
      ),
    );
  }
}
