import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/dialogs/audio_cue_config_dialog.dart';
import 'package:xcnav/dialogs/edit_gear.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/widgets/avatar_round.dart';

class MainMenu extends StatefulWidget {
  const MainMenu({super.key});

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
                  child: AvatarRound(Provider.of<Profile>(context).avatar, 40),
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
                          style: Theme.of(context).textTheme.headlineMedium,
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
                        color: Colors.grey.shade600,
                      ),
                      onPressed: () {
                        Navigator.pushNamed(context, "/profileEditor");
                      },
                    )),
              ])),
        ),

        // --- Gear
        Consumer<Profile>(
            builder: (context, profile, _) => Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(profile.gear?.wingMakeModel ?? "gear.wing unset".tr(),
                              style: Theme.of(context).textTheme.headlineSmall!.merge(TextStyle(
                                  color: profile.gear?.wingColor,
                                  // fontWeight: profile.gear?.wingMakeModel == null ? FontWeight.normal : FontWeight.bold,
                                  fontStyle:
                                      (profile.gear?.wingMakeModel == null ? FontStyle.italic : FontStyle.normal)))),
                          Text(profile.gear?.frameMakeModel ?? "gear.motor unset".tr(),
                              style: Theme.of(context).textTheme.headlineSmall!.merge(TextStyle(
                                  // color: profile.gear?.wingColor,
                                  // fontWeight:
                                  //     profile.gear?.frameMakeModel == null ? FontWeight.normal : FontWeight.bold,
                                  fontStyle:
                                      (profile.gear?.frameMakeModel == null ? FontStyle.italic : FontStyle.normal))))
                        ],
                      ),
                    ),
                    Positioned(
                        right: 0,
                        bottom: 0,
                        child: IconButton(
                          iconSize: 20,
                          icon: Icon(
                            Icons.edit,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () {
                            editGear(context, gear: profile.gear).then((newGear) {
                              setState(() {
                                if (newGear != null) {
                                  profile.gear = newGear;
                                }
                              });
                            });
                          },
                        )),
                  ],
                )),

        Divider(height: 20, thickness: 1, color: Colors.grey.shade700),

        // --- ADSB
        ListTile(
            minVerticalPadding: 20,
            leading: const Icon(Icons.radar, size: 30),
            title: Text("ADSB-in", style: Theme.of(context).textTheme.headlineSmall),
            trailing: Switch.adaptive(
              activeColor: Colors.lightBlue,
              value: Provider.of<ADSB>(context).enabled,
              onChanged: (value) => {Provider.of<ADSB>(context, listen: false).enabled = value},
            ),
            subtitle: Provider.of<ADSB>(context).enabled
                ? (Provider.of<ADSB>(context).lastHeartbeat > DateTime.now().millisecondsSinceEpoch - 1000 * 60)
                    ? Text.rich(TextSpan(children: [
                        WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.check,
                              color: Colors.green,
                            )),
                        TextSpan(text: "  ${"Connected".tr()}")
                      ]))
                    : Text.rich(TextSpan(children: [
                        const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.link_off,
                              color: Colors.amber,
                            )),
                        TextSpan(text: "  ${"No Data".tr()}"),
                        WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 15),
                              child: GestureDetector(
                                  onTap: () => {Navigator.popAndPushNamed(context, "/adsbHelp")},
                                  child: const Icon(Icons.help, size: 20, color: Colors.lightBlue)),
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
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                width: 30,
              ),
            ),
            ToggleButtons(
              borderWidth: 2,
              selectedBorderColor: Colors.lightBlue,
              selectedColor: Colors.lightBlue,
              constraints: const BoxConstraints.expand(width: 40, height: 40),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              isSelected: AudioCueService.modeOptions.values.map((e) => e == audioCueService.mode).toList(),
              onPressed: (index) {
                setState(() {
                  audioCueService.mode = AudioCueService.modeOptions.values.toList()[index];
                });
              },
              children: AudioCueService.modeOptions.keys.map((e) => Text("audio_cue.$e".tr())).toList(),
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

        // EXPERIMENTAL SERVO CARB
        if (settingsMgr.showServoCarbMenu.value)
          ListTile(
            iconColor: Colors.amber,
            textColor: Colors.amber,
            minVerticalPadding: 10,
            onTap: () => {Navigator.popAndPushNamed(context, "/servoCarb")},
            leading: const Icon(
              Icons.settings_applications_sharp,
              size: 30,
            ),
            title: Text(
              "ServoCarb",
              style: Theme.of(context).textTheme.headlineSmall!.merge(const TextStyle(color: Colors.amber)),
            ),
          ),

        Divider(height: 20, thickness: 1, color: Colors.grey.shade700),

        // Group
        ListTile(
          minVerticalPadding: 10,
          onTap: () => {Navigator.popAndPushNamed(context, "/groupDetails")},
          leading: const Icon(
            Icons.groups,
            size: 30,
          ),
          title: Text(
            "main_menu.group".tr(),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          trailing: IconButton(
              iconSize: 30,
              onPressed: () => {Navigator.popAndPushNamed(context, "/qrScanner")},
              icon: const Icon(
                Icons.person_add,
                color: Colors.lightGreen,
              )),
        ),

        // Checklist
        ListTile(
          minVerticalPadding: 10,
          leading: const Icon(Icons.checklist, size: 30),
          title: Text("main_menu.checklist".tr(), style: Theme.of(context).textTheme.headlineSmall),
          onTap: () => {Navigator.popAndPushNamed(context, "/checklist")},
        ),

        ListTile(
          minVerticalPadding: 10,
          leading: Image.asset(
            "assets/external/report_ppg.png",
            height: 30,
          ),
          title: Text("main_menu.weather".tr(), style: Theme.of(context).textTheme.headlineSmall),
          onTap: () => {Navigator.popAndPushNamed(context, "/weather")},
        ),

        ListTile(
            minVerticalPadding: 10,
            onTap: () => {Navigator.popAndPushNamed(context, "/flightLogs")},
            leading: const Icon(
              Icons.menu_book,
              size: 30,
            ),
            title: Text("main_menu.log".tr(), style: Theme.of(context).textTheme.headlineSmall)),

        Divider(height: 20, thickness: 1, color: Colors.grey.shade700),

        ListTile(
            minVerticalPadding: 10,
            onTap: () => {Navigator.popAndPushNamed(context, "/settings")},
            leading: const Icon(
              Icons.settings,
              size: 30,
            ),
            title: Text("main_menu.settings".tr(), style: Theme.of(context).textTheme.headlineSmall)),

        FutureBuilder(
            future: FlutterBluePlus.isSupported,
            builder: (context, supported) => (supported.hasData && (supported.data ?? false))
                ? ListTile(
                    minVerticalPadding: 10,
                    onTap: () => {Navigator.pushNamed(context, "/bleScan")},
                    leading: const Icon(Icons.bluetooth, size: 30),
                    title: Text("main_menu.devices".tr(), style: Theme.of(context).textTheme.headlineSmall),
                  )
                : Container()),

        ListTile(
          minVerticalPadding: 10,
          onTap: () => {Navigator.popAndPushNamed(context, "/about")},
          leading: const Icon(Icons.info, size: 30),
          title: Text("main_menu.about".tr(), style: Theme.of(context).textTheme.headlineSmall),
        ),
      ],
    ));
  }
}
