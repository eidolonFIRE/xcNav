import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/units.dart';

/// Flight duration along the top of the map. Tap to manually start / stop recording.
class FlightTimer extends StatelessWidget {
  const FlightTimer({super.key});

  void onTap(BuildContext context) {
    if (myTelemetry.inFlight) {
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
                content: Text("dialog.confirm.manual_stop".tr()),
                actions: [
                  ElevatedButton.icon(
                      icon: const Icon(
                        Icons.stop_circle,
                        color: Colors.red,
                      ),
                      onPressed: () {
                        myTelemetry.stopFlight();
                        Navigator.pop(context);
                      },
                      label: Text("btn.Stop".tr()))
                ],
              ));
    } else {
      myTelemetry.startFlight();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: myTelemetry,
        builder: (context, _) => GestureDetector(
              onTap: () => onTap(context),
              child: ClipRRect(
                  borderRadius:
                      const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                      child: Container(
                          color: Colors.white38,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (myTelemetry.takeOff != null)
                              Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: myTelemetry.inFlight
                                    ? const Icon(
                                        Icons.circle,
                                        color: Colors.red,
                                        size: 18,
                                      )
                                    : const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                              ),
                            if (myTelemetry.takeOff != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Text.rich(
                                  TextSpan(children: [
                                    richHrMin(
                                        duration:
                                            (myTelemetry.landing ?? DateTime.now()).difference(myTelemetry.flightStart!),
                                        valueStyle:
                                            Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black),
                                        unitStyle: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(color: Colors.grey.shade700),
                                        longUnits: true)
                                  ]),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            if (!settingsMgr.autoRecordFlight.value && myTelemetry.takeOff == null)
                              TextButton.icon(
                                  onPressed: () {
                                    myTelemetry.startFlight();
                                  },
                                  icon: const Icon(
                                    Icons.play_arrow,
                                    color: Colors.red,
                                  ),
                                  label: Text(
                                    "btn.Record".tr(),
                                    style: TextStyle(color: Colors.black),
                                  ))
                          ])))),
            ));
  }
}

/// Shown along the top of the map while the client is disconnected from the server.
class ConnectingBanner extends StatelessWidget {
  const ConnectingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
        color: Colors.amber,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Text.rich(
            TextSpan(children: [
              WidgetSpan(
                  child: Icon(
                Icons.language,
                size: 20,
                color: Colors.black,
              )),
              TextSpan(text: "  connecting", style: TextStyle(color: Colors.black, fontSize: 20)),
            ]),
          ),
        ));
  }
}
