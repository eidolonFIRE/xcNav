import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xcnav/dialogs/leave_group.dart';
import 'package:xcnav/dialogs/select_past_group.dart';

// Providers
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';

// Models
import 'package:xcnav/units.dart';

// Widgets
import 'package:xcnav/widgets/avatar_round.dart';

class GroupDetails extends StatefulWidget {
  const GroupDetails({super.key});

  @override
  State<GroupDetails> createState() => _GroupDetailsState();
}

class _GroupDetailsState extends State<GroupDetails> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  static const valueStyle = TextStyle(fontSize: 20, color: Colors.white);
  static const unitStyle = TextStyle(fontSize: 16, color: Colors.white);
  static const fillStyle = TextStyle(fontSize: 14, color: Colors.grey);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          "Group Members".tr(),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        actions: [
          IconButton(onPressed: () => {selectPastGroup(context)}, icon: const Icon(Icons.history)),
          IconButton(
              onPressed: () => {promptLeaveGroup(context)},
              icon: const Icon(
                Icons.logout,
                color: Colors.red,
              ))
        ],
      ),
      body: Consumer<Group>(
          builder: (context, group, child) => ListView(
              children: (group.pilots.isNotEmpty
                      ? group.pilots.values
                          .map((p) => ListTile(
                                leading: AvatarRound(p.avatar, 28),
                                title: Row(children: [
                                  Text(
                                    p.name,
                                    style: Theme.of(context).textTheme.headlineSmall,
                                  ),
                                ]),
                                trailing: p.geo == null
                                    ? Container()
                                    : IconButton(
                                        onPressed: () {
                                          SharePlus.instance.share(ShareParams(
                                              text: "${p.geo?.latlng.latitude},${p.geo?.latlng.longitude}"));
                                        },
                                        icon: Icon(
                                          Icons.share,
                                          color: Colors.blue,
                                        )),
                                subtitle: (group.activePilots.contains(p))
                                    ? Text.rich(TextSpan(children: [
                                        // speed
                                        richValue(UnitType.speed, p.geo!.spd,
                                            valueStyle: valueStyle, unitStyle: unitStyle),

                                        const TextSpan(style: fillStyle, text: ", at "),
                                        // alt
                                        richValue(UnitType.distFine, p.geo!.alt,
                                            valueStyle: valueStyle, unitStyle: unitStyle),

                                        const TextSpan(style: fillStyle, text: " MSL, "),
                                        // dist
                                        if (Provider.of<MyTelemetry>(context, listen: false).geo != null)
                                          richValue(UnitType.distCoarse,
                                              p.geo!.distanceTo(Provider.of<MyTelemetry>(context, listen: false).geo!),
                                              decimals: 1, valueStyle: valueStyle, unitStyle: unitStyle),
                                        if (Provider.of<MyTelemetry>(context, listen: false).geo != null)
                                          const TextSpan(style: fillStyle, text: " away"),
                                      ]))
                                    : (p.geo != null
                                        ? Text.rich(TextSpan(children: [
                                            const TextSpan(text: "( Telemetry is "),
                                            richHrMin(
                                                duration: DateTime.now()
                                                    .difference(DateTime.fromMillisecondsSinceEpoch(p.geo!.time)),
                                                valueStyle: valueStyle,
                                                unitStyle: unitStyle),
                                            const TextSpan(text: " old )"),
                                          ]))
                                        : const Text("( No Telemetry )")),
                              ))
                          .toList()
                      : [
                          ListTile(
                            title: Padding(
                              padding: EdgeInsets.all(30.0),
                              child: Text(
                                "empty_list".tr(),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                              ),
                            ),
                          )
                        ]) +
                  [
                    ListTile(
                        title: FloatingActionButton(
                      // iconSize: 35,
                      onPressed: () => {Navigator.pushNamed(context, "/qrScanner")},
                      heroTag: "group",
                      child: const Icon(
                        // Icons.qr_code_scanner,
                        Icons.person_add,
                        size: 30,
                        color: Colors.black,
                      ),
                    ))
                  ])),
    );
  }
}
