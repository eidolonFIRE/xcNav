import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/dialogs/wind_dialog.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';

/// Wind sock indicator. Tap to open the wind dialog.
///
/// All internal dimensions scale with [size] (designed at 90).
class Windicator extends StatelessWidget {
  final MyTelemetry myTelemetry;
  final double size;

  /// Overrides the default tap action (open the wind dialog).
  final VoidCallback? onTap;

  const Windicator({super.key, required this.myTelemetry, this.size = 90, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scale = size / 90;
    return Consumer<Wind>(
        builder: (context, wind, _) => ValueListenableBuilder<bool>(
            valueListenable: settingsMgr.northlockWind.listenable,
            builder: (context, northlockWind, _) {
              return GestureDetector(
                  onTap: onTap ??
                      () {
                        showDialog(context: context, builder: (context) => const WindDialog());
                      },
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale)),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 4 * scale,
                            top: 4 * scale,
                            child: Container(
                              width: 15 * scale,
                              height: 15 * scale,
                              transformAlignment: const Alignment(0, 0),
                              transform: Matrix4.rotationZ(
                                  northlockWind ? 0 : (wind.samples.isEmpty ? 0 : -wind.samples.last.hdg)),
                              child: northlockWind
                                  ? SvgPicture.asset(
                                      "assets/images/compass_north.svg",
                                      // fit: BoxFit.none,
                                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                    )
                                  : Transform.scale(
                                      scale: 1.4,
                                      child: SvgPicture.asset(
                                        "assets/images/compass.svg",
                                        // fit: BoxFit.none,
                                      ),
                                    ),
                            ),
                          ),
                          // Wind direction indicator
                          if (wind.result != null)
                            Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  transformAlignment: const Alignment(0, 0),
                                  transform: Matrix4.rotationZ(
                                      wind.result!.windHdg + (northlockWind ? 0 : -(myTelemetry.geo?.hdg ?? 0))),
                                  child: SvgPicture.asset(
                                    "assets/images/wind_sock.svg",
                                    width: 80 * scale,
                                    height: 80 * scale,
                                  ),
                                )),
                          if (wind.result != null)
                            Align(
                                alignment: Alignment.center,
                                child: Text(
                                  printValue(UnitType.speed, wind.result?.windSpd, digits: 2, decimals: 0) ?? "",
                                  style:
                                      TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16 * scale),
                                )),
                          if (wind.result == null)
                            Center(
                                child: Text(
                              "?",
                              style: TextStyle(color: Colors.grey, fontSize: 20 * scale),
                            ))
                        ],
                      ),
                    ),
                  ));
            }));
  }
}
