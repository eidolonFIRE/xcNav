import 'package:flutter/material.dart';

class AvatarRound extends StatelessWidget {
  final Image? avatar;
  final double radius;

  const AvatarRound(this.avatar, this.radius, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.loose, children: [
      // Relative Altitude Indicator

      CircleAvatar(
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
      ),
    ]);
  }
}
