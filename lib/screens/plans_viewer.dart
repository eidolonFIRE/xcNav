import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

// --- Dialogs
import 'package:xcnav/dialogs/save_plan.dart';

// --- Models
import 'package:xcnav/models/flight_plan.dart';

// --- Providers
// import 'package:xcnav/providers/active_plan.dart';

// --- Widgets
import 'package:xcnav/widgets/plan_card.dart';

class PlansViewer extends StatefulWidget {
  const PlansViewer({Key? key}) : super(key: key);

  @override
  State<PlansViewer> createState() => _PlansViewerState();
}

class _PlansViewerState extends State<PlansViewer> {
  Map<String, FlightPlan> plans = {};
  bool loaded = false;

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
    final Directory _appDocDirFolder = Directory("${_appDocDir.path}/flight_plans/");
    if (await _appDocDirFolder.exists()) {
      setState(() {
        loaded = false;
      });
      plans.clear();
      // Async load in all the files

      var files = await _appDocDirFolder.list(recursive: false, followLinks: false).toList();
      // debugPrint("${files.length} log files found.");
      List<Completer> completers = [];
      for (var each in files) {
        var _completer = Completer();
        completers.add(_completer);
        File.fromUri(each.uri).readAsString().then((value) {
          var _plan = FlightPlan.fromJson(each.uri.pathSegments.last.replaceAll(".json", ""), jsonDecode(value));
          if (_plan.waypoints.isNotEmpty) {
            plans[each.uri.path] = _plan;
          } else {
            // plan was empty, delete it
            File planFile = File.fromUri(each.uri);
            planFile.exists().then((value) {
              planFile.delete();
            });
          }

          _completer.complete();
        });
      }
      // debugPrint("${completers.length} completers created.");
      Future.wait(completers.map((e) => e.future).toList()).then((value) {
        setState(() {
          loaded = true;
        });
      });
    } else {
      debugPrint('"flight_plans" directory doesn\'t exist yet!');
    }
  }

  void selectKmlImport() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      file.readAsString().then((data) {
        // TODO: remove extension
        var newPlan = FlightPlan.fromKml(result.files.single.name, data);
        // TODO: notify if broken file
        if (newPlan.goodFile) {
          setState(() {
            plans[result.files.single.path!] = newPlan;
          });
        }
      });
    } else {
      // User canceled the picker
    }
  }

  @override
  Widget build(BuildContext context) {
    var keys = plans.keys.toList();
    keys.sort((a, b) => a.compareTo(b));
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flight Plans"),
        // centerTitle: true,
        actions: [
          IconButton(
              iconSize: 30,
              onPressed: () => {savePlan(context).then((value) => refreshPlansFromDirectory())},
              icon: const Icon(Icons.save_as)),
          IconButton(iconSize: 30, onPressed: () => {selectKmlImport()}, icon: const Icon(Icons.file_upload_outlined))
        ],
      ),
      body: !loaded
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView.builder(
              itemCount: plans.length,
              itemBuilder: (context, index) => PlanCard(plans[keys[index]]!, refreshPlansFromDirectory),
            ),
    );
  }
}
