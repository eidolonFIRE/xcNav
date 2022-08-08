import 'package:flutter/material.dart';
import 'package:xcnav/audio_cue_service.dart';

Future<Map<String, int>?> showAudioCueConfigDialog(BuildContext context, Map<String, int> config) {
  return showDialog<Map<String, int>>(
    context: context,
    builder: (context) => StatefulBuilder(
        builder: ((context, setState) => SimpleDialog(children: [
              // --- My Telemetry
              SwitchListTile(
                  value: config["myTelemetry"] == 1,
                  title: const Text("My Telemetry"),
                  onChanged: (newValue) => setState(
                        () => {config["myTelemetry"] = newValue ? 1 : 0},
                      )),

              // --- Next Waypoint
              SwitchListTile(
                  value: config["etaNext"] == 1,
                  title: const Text("Next Waypoint"),
                  onChanged: (newValue) => setState(
                        () => {config["etaNext"] = newValue ? 1 : 0},
                      )),

              // --- Remaining Trip
              ListTile(
                title: const Text("Remaining Trip"),
                trailing: ToggleButtons(
                  borderWidth: 2,
                  selectedBorderColor: Colors.lightBlueAccent,
                  selectedColor: Colors.lightBlueAccent,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                  constraints: const BoxConstraints(minHeight: 30, minWidth: 40),
                  isSelected: AudioCueService.configOptions["etaTrip"]!.map((e) => e == config["etaTrip"]).toList(),
                  onPressed: ((index) => setState(
                        () => config["etaTrip"] = AudioCueService.configOptions["etaTrip"]![index],
                      )),
                  children: AudioCueService.configOptions["etaTrip"]!
                      // ignore: unnecessary_string_interpolations
                      .map((e) => Text("${e == 0 ? "Off" : (e == 1 ? "Every" : "1/$e")}"))
                      .toList(),
                ),
              ),

              // --- Chat
              SwitchListTile(
                  value: config["groupChat"] == 1,
                  title: const Text("Chat Messages"),
                  onChanged: (newValue) => setState(
                        () => {config["groupChat"] = newValue ? 1 : 0},
                      )),

              // --- Group Awareness
              ListTile(
                title: const Text("Group Awareness"),
                trailing: ToggleButtons(
                  borderWidth: 2,
                  selectedBorderColor: Colors.lightBlueAccent,
                  selectedColor: Colors.lightBlueAccent,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                  constraints: const BoxConstraints(minHeight: 30, minWidth: 40),
                  isSelected: AudioCueService.configOptions["groupAwareness"]!
                      .map((e) => e == config["groupAwareness"])
                      .toList(),
                  onPressed: ((index) => setState(
                        () => config["groupAwareness"] = AudioCueService.configOptions["groupAwareness"]![index],
                      )),
                  children: AudioCueService.configOptions["groupAwareness"]!
                      // ignore: unnecessary_string_interpolations
                      .map((e) => Text("${e == 0 ? "Off" : (e == 1 ? "Less" : "More")}"))
                      .toList(),
                ),
              ),

              // --- Accept Changes
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 16),
                  child: IconButton(
                      icon: const Icon(Icons.check, color: Colors.lightGreen),
                      onPressed: () => Navigator.pop(context, config)),
                )
              ])
            ]))),
  );
}
