import 'package:flutter/material.dart';
import 'package:xcnav/models/waypoint.dart';

const iconOptions = {
  null: Icons.circle,
  "star": Icons.star,
  "x": Icons.close,
  "paraglider": Icons.paragliding,
  "exclamation": Icons.priority_high,
  "question": Icons.question_mark,
  "fuel": Icons.local_gas_station,
  "left": Icons.turn_left,
  "right": Icons.turn_right,
  "sleep": Icons.local_hotel,
  "flag": Icons.sports_score,
  "camera": Icons.photo_camera,
  "airport": Icons.local_airport,
  // TODO: add custom icons (camping tent, pylons, power lines?, LZ, etc)
};

var colorOptions = {
  "black": Colors.black,
  "red": Colors.red.shade700,
  "orange": Colors.amber.shade900,
  "blue": Colors.blue.shade800,
  "green": Colors.green.shade800,
  "purple": Colors.purple.shade600,
};

class MapMarker extends StatelessWidget {
  final Waypoint waypoint;
  final double size;

  const MapMarker(this.waypoint, this.size, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Image.asset(
        "assets/images/pin.png",
        color: waypoint.color == null ? Colors.black : Color(waypoint.color!),
      ),
      if (waypoint.icon != null)
        Center(
          child: Container(
            transform: Matrix4.translationValues(0, -size / 5.5, 0),
            child: Icon(
              iconOptions[waypoint.icon],
              size: size / 2,
            ),
          ),
        ),
    ]);
  }
}
