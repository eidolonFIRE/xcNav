import 'package:flutter/material.dart';
import 'package:xcnav/util/waypoint.dart';

class WaypointCard extends StatelessWidget {
  const WaypointCard({Key? key, required this.waypoint, required this.index, required this.onSelect, required this.isSelected}) : super(key: key);

  final Waypoint waypoint;
  final int index;
  final bool isSelected;

  // callbacks
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected ? Colors.blue : null,
      key: ValueKey(waypoint),
      margin: const EdgeInsets.all(1),
      child: ListTile(
        leading: Image.asset("assets/images/wp" + (waypoint.latlng.length > 1 ? "_path" : "") + (waypoint.isOptional ? "_optional" : "") + ".png"),
        title: TextButton(
          child: Text(waypoint.name, style: const TextStyle(color: Colors.white, fontSize: 30),),
          onPressed: onSelect,
        ),
        trailing:  ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
      ),
    );
  }
}