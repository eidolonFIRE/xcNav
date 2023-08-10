import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/dialogs/audio_cue_config_dialog.dart';
import 'package:xcnav/dialogs/edit_gear.dart';
import 'package:xcnav/dialogs/fuel_report_dialog.dart';
import 'package:xcnav/endpoint.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/units.dart';
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
                          Text(profile.gear?.wingMakeModel ?? "wing unset",
                              style: Theme.of(context).textTheme.headlineSmall!.merge(TextStyle(
                                  color: profile.gear?.wingColor,
                                  // fontWeight: profile.gear?.wingMakeModel == null ? FontWeight.normal : FontWeight.bold,
                                  fontStyle:
                                      (profile.gear?.wingMakeModel == null ? FontStyle.italic : FontStyle.normal)))),
                          Text(profile.gear?.frameMakeModel ?? "motor unset",
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
                                profile.gear = newGear;
                              });
                            });
                          },
                        )),
                  ],
                )),

        Divider(height: 20, thickness: 1, color: Colors.grey.shade700),

        // --- Fuel Reports
        Consumer<MyTelemetry>(builder: (context, myTelemetry, _) {
          const unitStyle = TextStyle(color: Colors.grey, fontSize: 14);

          void addFuelReport() {
            Navigator.pop(context);
            fuelReportDialog(context, DateTime.now(), null).then((report) {
              if (report != null && report.amount >= 0) {
                myTelemetry.addFuelReport(report.time, report.amount);
              }
            });
          }

          return Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 20, 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Icon(
                  Icons.local_gas_station,
                  size: 30,
                ),
                if (myTelemetry.fuelReports.isEmpty)
                  ElevatedButton.icon(
                      // style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      onPressed: addFuelReport,
                      icon: const Icon(
                        Icons.add,
                        color: Colors.lightBlue,
                        // size: 30,
                      ),
                      label: Text(
                        "Report Fuel",
                        style: Theme.of(context).textTheme.bodyLarge,
                      )),
                if (myTelemetry.fuelReports.isNotEmpty)
                  Card(
                    color: Colors.grey.shade900,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        DefaultTextStyle(
                          style: Theme.of(context).textTheme.titleLarge!.merge(const TextStyle(color: Colors.grey)),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text.rich(TextSpan(children: [
                              richHrMin(duration: (DateTime.now().difference(myTelemetry.fuelReports.last.time))),
                              const TextSpan(text: " ago: "),
                              richValue(UnitType.fuel, myTelemetry.fuelReports.last.amount,
                                  decimals: 1, valueStyle: const TextStyle(color: Colors.white))
                            ])),
                          ),
                        ),
                        if (myTelemetry.sumFuelStat != null)
                          DefaultTextStyle(
                            style: Theme.of(context).textTheme.bodyLarge!,
                            child: Text.rich(TextSpan(children: [
                              TextSpan(
                                  text:
                                      unitConverters[UnitType.fuel]!(myTelemetry.sumFuelStat!.rate).toStringAsFixed(1)),
                              TextSpan(text: "${getUnitStr(UnitType.fuel)}/hr", style: unitStyle),
                              const TextSpan(text: "   "),
                              TextSpan(
                                  text: unitConverters[UnitType.distCoarse]!(
                                          myTelemetry.sumFuelStat!.mpl / unitConverters[UnitType.fuel]!(1))
                                      .toStringAsFixed(1)),
                              TextSpan(
                                  text: "${getUnitStr(UnitType.distCoarse)}/${getUnitStr(UnitType.fuel)}",
                                  style: unitStyle),
                            ])),
                          )
                      ]),
                    ),
                  ),
                if (myTelemetry.fuelReports.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.lightBlue, size: 30),
                    onPressed: addFuelReport,
                  ),
                if (myTelemetry.fuelReports.isEmpty) Container()
              ]));
        }),

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
                color: Colors.white,
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

        // Group
        ListTile(
          minVerticalPadding: 10,
          onTap: () => {Navigator.popAndPushNamed(context, "/groupDetails")},
          leading: const Icon(
            Icons.groups,
            size: 30,
          ),
          title: Text(
            "Group",
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
          title: Text("Checklist", style: Theme.of(context).textTheme.headlineSmall),
          onTap: () => {Navigator.popAndPushNamed(context, "/checklist")},
        ),

        // NOTE: Weather is only available in NorthAmerica until more weather sources can be added
        if (localeZone == "NA")
          ListTile(
            minVerticalPadding: 10,
            leading: const Icon(
              Icons.cloudy_snowing,
              size: 30,
            ),
            title: Text("Weather", style: Theme.of(context).textTheme.headlineSmall),
            onTap: () => {Navigator.popAndPushNamed(context, "/weather")},
          ),

        ListTile(
            minVerticalPadding: 10,
            onTap: () => {Navigator.popAndPushNamed(context, "/flightLogs")},
            leading: const Icon(
              Icons.menu_book,
              size: 30,
            ),
            title: Text("Log", style: Theme.of(context).textTheme.headlineSmall)),

        Divider(height: 20, thickness: 1, color: Colors.grey.shade700),

        ListTile(
            minVerticalPadding: 10,
            onTap: () => {Navigator.popAndPushNamed(context, "/settings")},
            leading: const Icon(
              Icons.settings,
              size: 30,
            ),
            title: Text("Settings", style: Theme.of(context).textTheme.headlineSmall)),

        ListTile(
          minVerticalPadding: 10,
          onTap: () => {Navigator.popAndPushNamed(context, "/about")},
          leading: const Icon(Icons.info, size: 30),
          title: Text("About", style: Theme.of(context).textTheme.headlineSmall),
        ),
      ],
    ));
  }
}
