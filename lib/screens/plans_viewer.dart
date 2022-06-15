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
import 'package:xcnav/widgets/flight_plan_summary.dart';

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
      //if folder already exists return path
      plans.clear();
      // Async load in all the files

      var files = await _appDocDirFolder.list(recursive: false, followLinks: false).toList();
      debugPrint("${files.length} log files found.");
      List<Completer> completers = [];
      for (var each in files) {
        var _completer = Completer();
        completers.add(_completer);
        File.fromUri(each.uri).readAsString().then((value) {
          plans[each.uri.path] = FlightPlan.fromJson(each.path, jsonDecode(value));
          _completer.complete();
        });
      }
      debugPrint("${completers.length} completers created.");
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
        var newPlan = FlightPlan.fromKml(result.files.single.path!, data);
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
    keys.sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flight Plans"),
        // centerTitle: true,
        actions: [
          IconButton(
              onPressed: () => {savePlan(context).then((value) => refreshPlansFromDirectory())},
              icon: const Icon(Icons.save_as)),
          IconButton(onPressed: () => {selectKmlImport()}, icon: const Icon(Icons.file_upload_outlined))
        ],
      ),
      body: ListView.builder(
        itemCount: plans.length,
        itemBuilder: (context, index) => FlightPlanSummary(plans[keys[index]]!, refreshPlansFromDirectory),
      ),
    );
  }
}
