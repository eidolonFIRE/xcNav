import 'package:flutter/material.dart';
import 'package:xcnav/models/waypoint.dart';

const iconOptions = {
  "star": Icons.star,
  "square": Icons.square_rounded,
  "x": Icons.close,
  "paraglider": Icons.paragliding,
  "takeoff": Icons.flight_takeoff,
  "landing": Icons.flight_land,
  "exclamation": Icons.priority_high,
  "question": Icons.question_mark,
  "fuel": Icons.local_gas_station,
  "left": Icons.turn_left,
  "right": Icons.turn_right,
  "sleep": Icons.local_hotel,
  "flag": Icons.sports_score,
};

var colorOptions = {
  "black": Colors.black,
  "red": Colors.red[700],
  "amber": Colors.amber[800],
  "blue": Colors.blue[700],
  "green": Colors.green[800],
  "purple": Colors.purple[700],
};

class MapMarker extends StatelessWidget {
  final Waypoint waypoint;
  final double size;

  const MapMarker(this.waypoint, this.size, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(
        transform: Matrix4.translationValues(0, -size / 2, 0),
        child: Image.asset(
          "assets/images/pin.png",
          color: waypoint.color == null ? Colors.black : Color(waypoint.color!),
        ),
      ),
      if (waypoint.icon != null)
        Center(
          child: Container(
            transform: Matrix4.translationValues(0, -size / 1.5, 0),
            child: Icon(
              iconOptions[waypoint.icon],
              size: size / 2,
            ),
          ),
        ),
    ]);
  }
}
