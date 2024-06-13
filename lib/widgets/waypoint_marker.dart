import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:xcnav/models/waypoint.dart';

final iconOptions = {
  null: Icons.circle,
  "star": Icons.star,
  "x": Icons.close,
  "question": Icons.question_mark,
  "exclamation": Icons.priority_high,
  "flag": Icons.sports_score,
  "airport": Icons.local_airport,
  "windsock": "assets/images/icon_windsock.svg",
  "camp": "assets/images/icon_camp.svg",
  "paraglider": Icons.paragliding,
  "left": Icons.turn_left,
  "right": Icons.turn_right,
  "fuel": Icons.local_gas_station,
  "sleep": Icons.local_hotel,
  "camera": Icons.photo_camera,
  "takeoff": Icons.flight_takeoff,
  "landing": Icons.flight_land,
};

Widget getWpIcon(String? name, double size, Color? color) {
  final icon = iconOptions[name];

  if (name == "PATH") {
    return SizedBox(
        width: size,
        height: size,
        child: SvgPicture.asset("assets/images/path.svg",
            colorFilter: ColorFilter.mode(color ?? Colors.white, BlendMode.srcIn)));
  }

  if (icon is IconData || icon == null) {
    return Icon(
      iconOptions.keys.contains(name) ? iconOptions[name] as IconData : null,
      size: size,
      color: color,
    );
  } else if (icon is String) {
    return SizedBox(
      width: size,
      child: SvgPicture.asset(
        icon,
        colorFilter: ColorFilter.mode(color ?? Colors.white, BlendMode.srcIn),
        width: size,
        height: size,
      ),
    );
  } else {
    debugPrint("NULL WP ICON IMAGE!");
    return Container();
  }
}

var colorOptions = {
  "black": Colors.black,
  "red": Colors.red.shade700,
  "orange": Colors.amber.shade900,
  "blue": Colors.blue.shade800,
  "green": Colors.green.shade800,
  "purple": Colors.purple.shade600,
};

class WaypointMarker extends StatelessWidget {
  final Waypoint waypoint;
  final double size;

  const WaypointMarker(this.waypoint, this.size, {super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Center(
        child: SvgPicture.asset("assets/images/pin.svg",
            colorFilter:
                ColorFilter.mode(waypoint.color == null ? Colors.black : Color(waypoint.color!), BlendMode.srcIn)),
      ),
      if (waypoint.icon != null)
        Center(
          child: Container(
            transform: Matrix4.translationValues(0, -size / 5.5, 0),
            child: getWpIcon(waypoint.icon, size / 2, Colors.white),
          ),
        ),
    ]);
  }
}
