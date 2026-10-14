import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xcnav/dialogs/leave_group.dart';
import 'package:xcnav/dialogs/select_past_group.dart';

// Providers
import 'package:xcnav/providers/client.dart';
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
  final TextEditingController inputGroupId = TextEditingController();
  final groupCodeExp = RegExp(r'^([0-9a-zA-Z]{6,})$');

  @override
  void dispose() {
    inputGroupId.dispose();
    super.dispose();
  }

  bool handleCode(String code) {
    if (groupCodeExp.hasMatch(code)) {
      debugPrint("Joined code: $code");

      Provider.of<Client>(context, listen: false).joinGroup(context, code);
      inputGroupId.clear();
      FocusScope.of(context).unfocus();
      return true;
    } else {
      debugPrint("Invalid code: $code");
      return false;
    }
  }

  Widget buildGroupCodeCard(BuildContext context) {
    final groupId = Provider.of<Group>(context).currentGroupID?.toUpperCase();
    return Card(
      margin: const EdgeInsets.all(10),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- See current code
            Text(
              "Current Group".tr(),
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            (groupId == null)
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                  )
                : TextButton.icon(
                    iconAlignment: IconAlignment.end,
                    onPressed: () => {SharePlus.instance.share(ShareParams(text: groupId))},
                    icon: const Icon(
                      Icons.share,
                      color: Colors.blue,
                    ),
                    label: Text(
                      groupId,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),

            // --- Enter new code
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28),
                    textCapitalization: TextCapitalization.characters,
                    enableIMEPersonalizedLearning: false,
                    keyboardType: TextInputType.name,
                    decoration: InputDecoration(hintText: "Join Code".tr()),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9]"))],
                    controller: inputGroupId,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (text) => {handleCode(text)},
                  ),
                ),
                IconButton(
                    iconSize: 30,
                    onPressed: () => {handleCode(inputGroupId.text)},
                    icon: const Icon(
                      Icons.login,
                      color: Colors.green,
                    ))
              ],
            ),
          ],
        ),
      ),
    );
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
      body: Column(children: [
        buildGroupCodeCard(context),
        Expanded(
          // ListTile ink must paint on a Material inside the list, not the Scaffold's
          child: Material(
            type: MaterialType.transparency,
            clipBehavior: Clip.hardEdge,
            child: Consumer<Group>(
                builder: (context, group, child) => ListView(
                    children: group.pilots.values
                        .map((p) => ListTile(
                              leading: AvatarRound(p.avatar, 28),
                              title: Row(children: [
                                Text(
                                  p.name,
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                              ]),
                              trailing: p.geo == null
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        SharePlus.instance.share(
                                            ShareParams(text: "${p.geo?.latlng.latitude},${p.geo?.latlng.longitude}"));
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
                                      if (myTelemetry.geo != null)
                                        richValue(UnitType.distCoarse, p.geo!.distanceTo(myTelemetry.geo!),
                                            decimals: 1, valueStyle: valueStyle, unitStyle: unitStyle),
                                      if (myTelemetry.geo != null) const TextSpan(style: fillStyle, text: " away"),
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
                        .toList())),
          ),
        ),
      ]),
    );
  }
}
