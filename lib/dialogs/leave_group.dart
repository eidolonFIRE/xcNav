import 'package:easy_localization/easy_localization.dart';
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
            "dialog.confirm.leave_group".tr(),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          titlePadding: const EdgeInsets.all(10),
          contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          actions: [
            ElevatedButton.icon(
                label: Text("btn.Leave".tr()),
                onPressed: () {
                  Provider.of<Client>(context, listen: false).joinGroup(context, "");
                  Navigator.popUntil(context, ModalRoute.withName("/home"));
                },
                icon: const Icon(
                  Icons.logout,
                  size: 24,
                  color: Colors.red,
                )),
          ],
        );
      });
}
