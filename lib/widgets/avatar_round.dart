import 'package:flutter/material.dart';

class AvatarRound extends StatelessWidget {
  final Widget? avatar;
  final double radius;

  const AvatarRound(this.avatar, this.radius, {super.key});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: SizedBox(
              width: radius * 2,
              height: radius * 2,
              child: FittedBox(fit: BoxFit.fill, child: avatar ?? Image.asset("assets/images/default_avatar.png"))),
        ),
      ),
    );
  }
}
