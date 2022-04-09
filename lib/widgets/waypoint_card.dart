import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/providers/group.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/widgets/avatar_round.dart';

class WaypointCard extends StatelessWidget {
  const WaypointCard(
      {Key? key,
      required this.waypoint,
      required this.index,
      required this.onSelect,
      required this.onToggleOptional,
      required this.isSelected})
      : super(key: key);

  final Waypoint waypoint;
  final int index;
  final bool isSelected;

  // callbacks
  final VoidCallback onSelect;
  final VoidCallback onToggleOptional;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected ? Colors.blue : null,
      key: ValueKey(waypoint),
      margin: const EdgeInsets.all(1),
      child: ListTile(
        selected: isSelected,
        selectedColor: Colors.black,
        contentPadding: EdgeInsets.zero,
        leading: IconButton(
          onPressed: onToggleOptional,
          padding: EdgeInsets.zero,
          iconSize: 60,
          icon: Image.asset("assets/images/wp" +
              (waypoint.latlng.length > 1 ? "_path" : "") +
              (waypoint.isOptional ? "_optional" : "") +
              ".png"),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          children: [
            TextButton(
              child: Container(
                constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width / 4),
                child: Text(
                  waypoint.name,
                  style: const TextStyle(color: Colors.white, fontSize: 30),
                ),
              ),
              onPressed: onSelect,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: Provider.of<Group>(context)
                  .pilots
                  .values
                  .where((element) => element.selectedWaypoint == index)
                  .map((e) => AvatarRound(e.avatar, 20))
                  .toList(),
            )
          ],
        ),
        trailing: ReorderableDragStartListener(
          index: index,
          child: const Icon(
            Icons.drag_handle,
            size: 25,
          ),
        ),
      ),
    );
  }
}
