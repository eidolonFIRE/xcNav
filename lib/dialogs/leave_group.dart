import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:xcnav/providers/client.dart';

final TextEditingController newWaypointName = TextEditingController();

void promptLeaveGroup(BuildContext context) {
  showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            "Leave Group?",
            style: Theme.of(context).textTheme.headline4,
          ),
          titlePadding: const EdgeInsets.all(10),
          contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          // content: Column(
          //   mainAxisSize: MainAxisSize.min,
          //   children: [

          //   ],
          // ),
          actions: [
            ElevatedButton.icon(
                label: const Text("Leave"),
                onPressed: () {
                  Provider.of<Client>(context, listen: false).leaveGroup(false);
                  Navigator.popUntil(context, ModalRoute.withName("/home"));
                },
                icon: const Icon(
                  Icons.logout,
                  size: 24,
                  color: Colors.red,
                )),
            // ElevatedButton.icon(
            //     label: const Text("Cancel"),
            //     onPressed: () => {Navigator.pop(context)},
            //     icon: const Icon(
            //       Icons.cancel,
            //       size: 20,
            //       color: Colors.lightGreen,
            //     )),
          ],
        );
      });
}
