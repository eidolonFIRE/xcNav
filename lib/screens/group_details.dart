import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/dialogs/leave_group.dart';
import 'package:xcnav/dialogs/select_past_group.dart';
import 'package:xcnav/patreon.dart';

// Providers
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/settings.dart';

// Models
import 'package:xcnav/units.dart';

// Widgets
import 'package:xcnav/widgets/avatar_round.dart';

class GroupDetails extends StatefulWidget {
  const GroupDetails({Key? key}) : super(key: key);

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
  static final fillStyle = TextStyle(fontSize: 14, color: Colors.grey.shade600);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(
            "Group Members",
            style: Theme.of(context).textTheme.headline6,
          ),
          actions: [
            IconButton(
                iconSize: 35,
                onPressed: () => {Navigator.pushNamed(context, "/qrScanner")},
                icon: const Icon(
                  Icons.qr_code_scanner,
                  color: Colors.lightBlue,
                )),
            const VerticalDivider(
              thickness: 2,
            ),
            IconButton(onPressed: () => {selectPastGroup(context)}, icon: const Icon(Icons.history)),
            IconButton(
                onPressed: () => {promptLeaveGroup(context)},
                icon: const Icon(
                  Icons.logout,
                  color: Colors.red,
                ))
          ],
        ),
        body: Consumer2<Group, Settings>(
            builder: (context, group, settings, child) => ListView(
                children: group.pilots.values
                    .map((p) => ListTile(
                          leading: AvatarRound(p.avatar, 28, tier: p.tier),
                          title: Row(children: [
                            Text(
                              p.name,
                              style: Theme.of(context).textTheme.headline5,
                            ),
                            if (isTierRecognized(p.tier))
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: tierBadge(p.tier),
                              )
                          ]),
                          subtitle: (p.geo.time > DateTime.now().millisecondsSinceEpoch - 5000 * 60)
                              ? Text.rich(TextSpan(children: [
                                  // speed
                                  richValue(UnitType.speed, p.geo.spd, valueStyle: valueStyle, unitStyle: unitStyle),

                                  TextSpan(style: fillStyle, text: ", at "),
                                  // alt
                                  richValue(UnitType.distFine, p.geo.alt, valueStyle: valueStyle, unitStyle: unitStyle),

                                  TextSpan(style: fillStyle, text: " MSL, "),
                                  // dist
                                  richValue(
                                      UnitType.distCoarse, p.geo.distanceTo(Provider.of<MyTelemetry>(context).geo),
                                      valueStyle: valueStyle, unitStyle: unitStyle),

                                  TextSpan(style: fillStyle, text: " away"),
                                ]))
                              : Text.rich(TextSpan(children: [
                                  const TextSpan(text: "( Telemetry is "),
                                  richHrMin(
                                      duration:
                                          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(p.geo.time)),
                                      valueStyle: valueStyle,
                                      unitStyle: unitStyle),
                                  const TextSpan(text: " old )"),
                                ])),
                        ))
                    .toList())));
  }
}
