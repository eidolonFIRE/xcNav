import 'package:flutter/material.dart';

class FuelWarning extends StatefulWidget {
  final double size;

  const FuelWarning(this.size, {Key? key}) : super(key: key);

  @override
  State<FuelWarning> createState() => _FuelWarningState();
}

class _FuelWarningState extends State<FuelWarning>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<Color?> animation;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
        duration: const Duration(milliseconds: 1000), vsync: this);
    final CurvedAnimation curve =
        CurvedAnimation(parent: controller, curve: Curves.linear);
    animation =
        ColorTween(begin: Colors.amberAccent, end: Colors.red).animate(curve);
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.reverse();
      } else if (status == AnimationStatus.dismissed) {
        controller.forward();
      }
      setState(() {});
    });
    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: widget.size / 2,
      backgroundColor: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Center(
                  child: Icon(
                Icons.local_gas_station,
                size: widget.size * 0.75,
                color: animation.value,
              ))),
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
