import 'package:dart_numerics/dart_numerics.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/models/carb_needle.dart';

class CarbNeedleDial extends StatelessWidget {
  final CarbNeedle needle;
  final double size;
  final String? label;
  final VoidCallback? onUp;

  const CarbNeedleDial(this.needle, this.size, {this.label, this.onUp, super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
            // force space to be big to capture clicks
            // SizedBox(width: size * 2, height: size * 2),

            // Endstop tick
            Transform.rotate(
              angle: -needle.config.fov / 2,
              child: Transform.translate(
                offset: Offset(0, -size * 0.6),
                child: Container(
                  width: 5,
                  height: size / 6,
                  // height: 20,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            Transform.rotate(
              angle: needle.config.fov / 2,
              child: Transform.translate(
                offset: Offset(0, -size * 0.6),
                child: Container(
                  width: 5,
                  height: size / 6,
                  // height: 20,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            // Endstop Labels
            Transform.translate(
                offset: Offset.fromDirection(-piOver2 - needle.config.fov / 2, size * 0.85),
                child: const Text(
                  "Rich",
                  style: TextStyle(color: Colors.lightBlue, fontSize: 20),
                )),

            Transform.translate(
                offset: Offset.fromDirection(-piOver2 + needle.config.fov / 2, size * 0.85),
                child: const Text(
                  "Lean",
                  style: TextStyle(color: Colors.redAccent, fontSize: 20),
                )),
          ] +

          // --- Preset Labels: tick
          needle.config.presets.values
              .map((e) => Transform.rotate(
                    angle: e * needle.config.fov - needle.config.fov / 2,
                    child: Transform.translate(
                      offset: Offset(0, -size * 0.6),
                      child: Container(
                        width: 3,
                        height: size / 9,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ))
              .toList() +
          // --- Preset Labels: widget
          needle.config.presets.entries
              .map(
                (e) => Transform.translate(
                    offset:
                        Offset.fromDirection(e.value * needle.config.fov - needle.config.fov / 2 - piOver2, size * 0.8),
                    child: Text(e.key)),
              )
              .toList() +
          [
            // Main Dial
            Listener(
              onPointerDown: (_) {
                needle.pointerDown = true;
              },
              onPointerUp: (_) {
                needle.pointerDown = false;
                onUp?.call();
              },
              onPointerMove: (event) {
                if (needle.pointerDown) {
                  final delta = Offset(size / 2, size / 2) - event.localPosition;
                  final dir = (delta.direction + piOver2) % pi2 - piOver2;
                  needle.mixture = (dir - piOver2 + needle.config.fov / 2) / needle.config.fov;
                  // debugPrint("${needle.mixture}");
                }
              },
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  children: [
                    // bottom
                    Container(
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 4),
                          borderRadius: BorderRadius.circular(100),
                          color: Colors.white),
                    ),

                    // bar
                    ListenableBuilder(
                        listenable: needle,
                        builder: (context, _) {
                          return Transform.rotate(
                            angle: needle.mixture * needle.config.fov - needle.config.fov / 2,
                            child: Center(
                              child: Container(
                                width: size / 10,
                                // height: 20,
                                // color: Colors.black,
                                decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                  // transform: GradientRotation(piOver2),
                                  colors: [Colors.black, Color.fromARGB(255, 80, 80, 80)],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                )),
                              ),
                            ),
                          );
                        })
                  ],
                ),
              ),
            ),

            if (label != null)
              IgnorePointer(
                child: Text(
                  label!,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 40,
                      color: Colors.black,
                      shadows: [BoxShadow(color: Colors.white, blurRadius: 30)]),
                ),
              ),

            // Left arrow
            Padding(
              padding: EdgeInsets.only(top: size * 0.6, right: size * 1.6),
              child: IconButton(
                  onPressed: () {
                    needle.mixture = needle.mixture - 0.03;
                  },
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    color: Colors.lightBlue,
                  )),
            ),
            Padding(
              padding: EdgeInsets.only(top: size * 0.6, left: size * 1.6),
              child: IconButton(
                  onPressed: () {
                    needle.mixture = needle.mixture + 0.03;
                  },
                  icon: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.redAccent,
                  )),
            )
          ],
    );
  }
}
