import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/dialogs/leave_group.dart';

// Providers
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';

// Models
import 'package:xcnav/models/geo.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
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
                children: group.pilots.values
                    .map((_p) => ListTile(
                          leading: AvatarRound(_p.avatar, 28),
                          title: Text(
                            _p.name,
                            style: Theme.of(context).textTheme.headline5,
                          ),
                          subtitle: (_p.geo.time >
                                  DateTime.now().millisecondsSinceEpoch -
                                      5000 * 60)
                              ? Text(
                                  "${(_p.geo.distanceTo(Provider.of<MyTelemetry>(context).geo) * meters2Miles).toStringAsFixed(1)} mi away,   ${(_p.geo.alt * meters2Feet).toStringAsFixed(0)}' alt",
                                  style: Theme.of(context).textTheme.bodyMedium)
                              : const Text("( outdated telemetry )"),
                        ))
                    .toList())));
  }
}
