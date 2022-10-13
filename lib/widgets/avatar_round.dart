import 'package:flutter/material.dart';
import 'package:xcnav/patreon.dart';

class AvatarRound extends StatelessWidget {
  final Image? avatar;
  final double radius;
  final String? tier;

  const AvatarRound(this.avatar, this.radius, {Key? key, this.tier})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: tierColors[tier] ?? Colors.black,
      child: Padding(
        padding: EdgeInsets.all(isTierRecognized(tier) ? 3 : 2),
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
    );
  }
}
