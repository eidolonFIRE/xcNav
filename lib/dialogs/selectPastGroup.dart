import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/widgets/avatar_round.dart';

void selectPastGroup(BuildContext context) {
  var group = Provider.of<Group>(context, listen: false);
  showDialog(
      context: context,
      builder: (context) => AlertDialog(
          title: const Text("Recent Groups"),
          content: group.pastGroups.isEmpty
              ? const Text(
                  "Nothing here...\nHave you been in a group recently?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.grey),
                )
              : SizedBox(
                  width: MediaQuery.of(context).size.width * 0.75,
                  child: ListView.builder(
                    shrinkWrap: true,
                    reverse: true,
                    itemCount: group.pastGroups.length,
                    itemBuilder: (context, index) {
                      return Card(
                          color: Theme.of(context).backgroundColor,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            // fit: StackFit.expand,
                            children: group.pastGroups[index].pilots
                                    .map<Widget>((p) => Card(
                                          shape: const RoundedRectangleBorder(
                                              borderRadius: BorderRadius.all(
                                                  Radius.circular(16))),
                                          child: Padding(
                                            padding: const EdgeInsets.all(2.0),
                                            child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  AvatarRound(p.avatar, 16),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            6.0),
                                                    child: Text(p.name),
                                                  )
                                                ]),
                                          ),
                                        ))
                                    .toList() +
                                [
                                  Padding(
                                    padding: const EdgeInsets.all(13.0),
                                    child: Builder(builder: (context) {
                                      final delta = DateTime.now().difference(
                                          group.pastGroups[index].timestamp);
                                      final value = delta.inMinutes >= 60
                                          ? delta.inHours
                                          : delta.inMinutes;
                                      final unit =
                                          delta.inMinutes >= 60 ? "hr" : "min";
                                      return Text(
                                        "( $value $unit ago )",
                                        style: const TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey),
                                      );
                                    }),
                                  ),
                                  IconButton(
                                      visualDensity: VisualDensity.comfortable,
                                      onPressed: () {
                                        Provider.of<Client>(context,
                                                listen: false)
                                            .joinGroup(
                                                group.pastGroups[index].id);
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(
                                        Icons.login,
                                        color: Colors.lightGreen,
                                      ))
                                ],
                          ));
                    },
                  ),
                )));
}