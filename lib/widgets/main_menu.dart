import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/dialogs/audio_cue_config_dialog.dart';
import 'package:xcnav/patreon.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/widgets/avatar_round.dart';

class MainMenu extends StatefulWidget {
  const MainMenu({Key? key}) : super(key: key);

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  @override
  Widget build(BuildContext context) {
    return Drawer(
        child: ListView(
      children: [
        // --- Profile (menu header)
        SizedBox(
          height: 110,
          child: DrawerHeader(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 1, color: Colors.grey.shade700))),
              padding: EdgeInsets.zero,
              child: Stack(children: [
                Positioned(
                  left: 10,
                  top: 10,
                  child: AvatarRound(
                    Provider.of<Profile>(context).avatar,
                    40,
                    tier: Provider.of<Profile>(context, listen: false).tier,
                  ),
                ),
                Positioned(
                  left: 100,
                  right: 10,
                  top: 10,
                  bottom: 10,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Text(
                          Provider.of<Profile>(context).name ?? "???",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: Theme.of(context).textTheme.headline4,
                        ),
                      ]),
                ),
                Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton(
                      iconSize: 20,
                      icon: Icon(
                        Icons.edit,
                        color: Colors.grey.shade700,
                      ),
                      onPressed: () {
                        Navigator.pushNamed(context, "/profileEditor");
                      },
                    )),
                if (isTierRecognized(Provider.of<Profile>(context, listen: false).tier))
                  Positioned(top: 10, right: 10, child: tierBadge(Provider.of<Profile>(context, listen: false).tier)),
              ])),
        ),

        // --- Map Options
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Consumer<Settings>(
                  builder: (context, settings, _) => SizedBox(
                        child: ToggleButtons(
                            isSelected: Settings.mapTileThumbnails.keys.map((e) => e == settings.curMapTiles).toList(),
                            borderRadius: const BorderRadius.all(Radius.circular(10)),
                            borderWidth: 4,
                            borderColor: Colors.grey.shade900,
                            selectedBorderColor: Colors.lightBlue,
                            onPressed: (index) {
                              settings.curMapTiles = Settings.mapTileThumbnails.keys.toList()[index];
                            },
                            children: Settings.mapTileThumbnails.keys
                                .map((e) => Opacity(
                                      opacity: e == settings.curMapTiles ? 1.0 : 0.7,
                                      child: SizedBox(
                                        width: 80,
                                        height: 50,
                                        child: Settings.mapTileThumbnails[e],
                                      ),
                                    ))
                                .toList()),
                      )),
            ],
          ),
        ),

        // --- Map opacity slider
        if (Provider.of<Settings>(context).curMapTiles != "topo")
          Builder(builder: (context) {
            final settings = Provider.of<Settings>(context, listen: false);
            return Slider(
                label: "Opacity",
                activeColor: Colors.lightBlue,
                value: settings.mapOpacity(settings.curMapTiles),
                onChanged: (value) => settings.setMapOpacity(settings.curMapTiles, value));
          }),

        // --- Toggle airspace overlay
        // if (Provider.of<Settings>(context).curMapTiles == "topo")
        //   ListTile(
        //     minVerticalPadding: 20,
        //     leading: const Icon(
        //       Icons.local_airport,
        //       size: 30,
        //     ),
        //     title: Text("Airspace", style: Theme.of(context).textTheme.headline5),
        //     trailing: Switch(
        //       activeColor: Colors.lightBlueAccent,
        //       value: Provider.of<Settings>(context).showAirspace,
        //       onChanged: (value) => {Provider.of<Settings>(context, listen: false).showAirspace = value},
        //     ),
        //   ),

        // --- ADSB
        ListTile(
            minVerticalPadding: 20,
            leading: const Icon(Icons.radar, size: 30),
            title: Text("ADSB-in", style: Theme.of(context).textTheme.headline5),
            trailing: Switch(
              activeColor: Colors.lightBlueAccent,
              value: Provider.of<ADSB>(context).enabled,
              onChanged: (value) => {Provider.of<ADSB>(context, listen: false).enabled = value},
            ),
            subtitle: Provider.of<ADSB>(context).enabled
                ? (Provider.of<ADSB>(context).lastHeartbeat > DateTime.now().millisecondsSinceEpoch - 1000 * 60)
                    ? const Text.rich(TextSpan(children: [
                        WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.check,
                              color: Colors.green,
                            )),
                        TextSpan(text: "  Connected")
                      ]))
                    : Text.rich(TextSpan(children: [
                        const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.link_off,
                              color: Colors.amber,
                            )),
                        const TextSpan(text: "  No Data"),
                        WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 15),
                              child: GestureDetector(
                                  onTap: () => {Navigator.popAndPushNamed(context, "/adsbHelp")},
                                  child: const Icon(Icons.help, size: 20, color: Colors.lightBlueAccent)),
                            )),
                      ]))
                : null),

        // --- Audio Cues
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 22, 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SvgPicture.asset(
                "assets/external/text_to_speech.svg",
                color: Colors.white,
                width: 30,
              ),
            ),
            ToggleButtons(
              borderWidth: 2,
              selectedBorderColor: Colors.lightBlueAccent,
              selectedColor: Colors.lightBlueAccent,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 30),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              isSelected: AudioCueService.modeOptions.values.map((e) => e == audioCueService.mode).toList(),
              onPressed: (index) {
                setState(() {
                  audioCueService.mode = AudioCueService.modeOptions.values.toList()[index];
                });
              },
              children: AudioCueService.modeOptions.keys.map((e) => Text(e)).toList(),
            ),
            IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  showAudioCueConfigDialog(context, audioCueService.config).then((value) {
                    if (value != null) {
                      audioCueService.config = value;
                    }
                  });
                },
                icon: const Icon(Icons.settings)),
          ]),
        ),

        Divider(height: 20, thickness: 1, color: Colors.grey.shade700),

        /// Group
        ListTile(
          minVerticalPadding: 20,
          onTap: () => {Navigator.popAndPushNamed(context, "/groupDetails")},
          leading: const Icon(
            Icons.groups,
            size: 30,
          ),
          title: Text(
            "Group",
            style: Theme.of(context).textTheme.headline5,
          ),
          trailing: IconButton(
              iconSize: 30,
              onPressed: () => {Navigator.popAndPushNamed(context, "/qrScanner")},
              icon: const Icon(
                Icons.qr_code_scanner,
                color: Colors.lightBlue,
              )),
        ),

        ListTile(
          minVerticalPadding: 20,
          leading: const Icon(
            Icons.cloudy_snowing,
            size: 30,
          ),
          title: Text("Weather", style: Theme.of(context).textTheme.headline5),
          onTap: () => {Navigator.popAndPushNamed(context, "/weather")},
        ),

        ListTile(
            minVerticalPadding: 20,
            onTap: () => {Navigator.popAndPushNamed(context, "/flightLogs")},
            leading: const Icon(
              Icons.menu_book,
              size: 30,
            ),
            title: Text("Log", style: Theme.of(context).textTheme.headline5)),

        Divider(height: 20, thickness: 1, color: Colors.grey.shade700),

        ListTile(
            minVerticalPadding: 20,
            onTap: () => {Navigator.popAndPushNamed(context, "/settings")},
            leading: const Icon(
              Icons.settings,
              size: 30,
            ),
            title: Text("Settings", style: Theme.of(context).textTheme.headline5)),

        ListTile(
          minVerticalPadding: 20,
          onTap: () => {Navigator.popAndPushNamed(context, "/about")},
          leading: const Icon(Icons.info, size: 30),
          title: Text("About", style: Theme.of(context).textTheme.headline5),
        ),
      ],
    ));
  }
}
