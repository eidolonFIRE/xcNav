import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// --- Dialogs
import 'package:xcnav/dialogs/save_plan.dart';

// --- Models
import 'package:xcnav/models/flight_plan.dart';

// --- Providers
// import 'package:xcnav/providers/active_plan.dart';

// --- Widgets
import 'package:xcnav/widgets/flight_plan_summary.dart';

class PlansViewer extends StatefulWidget {
  const PlansViewer({Key? key}) : super(key: key);

  @override
  State<PlansViewer> createState() => _PlansViewerState();
}

class _PlansViewerState extends State<PlansViewer> {
  List<FlightPlan> plans = [];

  @override
  void initState() {
    super.initState();
    refreshPlansFromDirectory();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void refreshPlansFromDirectory() async {
    final Directory _appDocDir = await getApplicationDocumentsDirectory();
    final Directory _appDocDirFolder =
        Directory("${_appDocDir.path}/flight_plans/");
    if (await _appDocDirFolder.exists()) {
      //if folder already exists return path
      plans.clear();
      // Async load in all the files
      // TODO: ensure some sorted order (atm it's race)
      _appDocDirFolder
          .list(recursive: false, followLinks: false)
          .forEach((each) {
        File.fromUri(each.uri).readAsString().then((value) {
          plans.add(FlightPlan.fromJson(each.path, jsonDecode(value)));
          setState(() {});
        });
      });
      setState(() {});
    } else {
      debugPrint('"flight_plans" directory doesn\'t exist yet!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flight Plans"),
        centerTitle: true,
        actions: [
          IconButton(
              onPressed: () => {
                    savePlan(context)
                        .then((value) => refreshPlansFromDirectory())
                  },
              icon: const Icon(Icons.save_as)),
          IconButton(
              // TODO: implement import
              onPressed: () => {},
              icon: const Icon(Icons.file_upload_outlined))
        ],
      ),
      body: ListView(
        children: plans
            .map((e) => FlightPlanSummary(e, refreshPlansFromDirectory))
            .toList(),
      ),
    );
  }
}
