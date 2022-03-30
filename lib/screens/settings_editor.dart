import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';

// Providers
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/chat.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/settings.dart';

// Models
import 'package:xcnav/models/message.dart';
import 'package:xcnav/models/pilot.dart';

// Widgets
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/chat_bubble.dart';

class SettingsEditor extends StatefulWidget {
  const SettingsEditor({Key? key}) : super(key: key);

  @override
  State<SettingsEditor> createState() => _SettingsEditorState();
}

const TextStyle _entryLabel = TextStyle(fontSize: 20);

class _SettingsEditorState extends State<SettingsEditor> {
  final TextEditingController searchInput = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Consumer<Settings>(builder: ((context, settings, child) {
      return Scaffold(
          appBar: AppBar(
            title: SizedBox(
              height: 32,
              child: TextField(
                style: const TextStyle(fontSize: 24),
                controller: searchInput,
                decoration: InputDecoration(suffixIcon: Icon(Icons.search)),
              ),
            ),
          ),
          body: SettingsList(
            sections: [
              SettingsSection(
                  title: const Text("Debug Tools"),
                  tiles: <SettingsTile>[
                    // --- Toggle: Location Spoofing
                    SettingsTile.switchTile(
                      initialValue: settings.spoofLocation,
                      title: const Text("Spoof Location"),
                      leading: const Icon(Icons.location_off),
                      onToggle: (value) => {settings.spoofLocation = value},
                    ),
                    // --- Erase Identity
                    SettingsTile.navigation(
                      title: const Text("Clear Identity"),
                      leading: const Icon(
                        Icons.warning_amber,
                        color: Colors.red,
                      ),
                      onPressed: (value) => {
                        Provider.of<Profile>(context, listen: false)
                            .eraseIdentity()
                      },
                    )
                  ])
            ],
          ));
    }));
  }
}
