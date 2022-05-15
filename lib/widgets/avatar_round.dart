import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class AvatarRound extends StatelessWidget {
  final Image? avatar;
  final double radius;
  final double? hdg;

  const AvatarRound(this.avatar, this.radius, {Key? key, this.hdg})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.loose, children: [
      if (hdg != null)
        Container(
          // width: radius * 3,
          // height: radius * 3,
          // color: Colors.amber.withAlpha(100),
          transformAlignment: const Alignment(0, 0),
          transform:
              Matrix4.rotationZ(hdg!) * Matrix4.translationValues(0, -12, 0),
          child: SizedBox(
            // width: radius * 3,
            // height: radius * 3,
            child: SvgPicture.asset(
              "assets/images/pilot_direction_arrow.svg",
              // fit: BoxFit.none,
              clipBehavior: Clip.none,
              // width: radius,
              // height: radius,
            ),
          ),
        ),
      CircleAvatar(
        radius: radius,
        backgroundColor: Colors.black,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: ClipOval(
            child: SizedBox(
                width: radius * 2,
                height: radius * 2,
                child: FittedBox(
                    fit: BoxFit.fill,
                    child: avatar ??
                        Image.asset("assets/images/default_avatar.png"))),
          ),
        ),
      ),
    ]);
  }
}
