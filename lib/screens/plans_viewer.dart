import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/dialogs/edit_plan_name.dart';

// --- Dialogs
import 'package:xcnav/dialogs/save_plan.dart';
import 'package:xcnav/dialogs/select_kml_folders.dart';

// --- Models
import 'package:xcnav/models/flight_plan.dart';
import 'package:xcnav/providers/plans.dart';

// --- Providers
// import 'package:xcnav/providers/active_plan.dart';

// --- Widgets
import 'package:xcnav/widgets/plan_card.dart';
import 'package:xml/xml.dart';

class PlansViewer extends StatefulWidget {
  const PlansViewer({Key? key}) : super(key: key);

  @override
  State<PlansViewer> createState() => _PlansViewerState();
}

class _PlansViewerState extends State<PlansViewer> {
  void selectKmlImport(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ["kml"]);

    if (result != null) {
      File file = File(result.files.single.path!);
      file.readAsString().then((data) async {
        final document = XmlDocument.parse(data).getElement("kml")!.getElement("Document")!;

        // Select which folders to import
        final folderNames = document.findAllElements("Folder").toList();

        final selectedFolderOptions = await selectKmlFolders(context, folderNames);
        final selectedFolders = folderNames.isNotEmpty ? selectedFolderOptions?.folders : null;
        var newPlan = FlightPlan.fromKml(result.files.single.name, document, selectedFolders ?? [],
            setAllOptional: selectedFolderOptions?.allOptional ?? false);
        // TODO: notify if broken file
        if (newPlan.goodFile) {
          Provider.of<Plans>(context, listen: false).setPlan(newPlan);
        }
      });
    } else {
      // User canceled the picker
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<Plans>(builder: ((context, plans, child) {
      var keys = plans.loadedPlans.keys.toList();
      keys.sort((a, b) => a.compareTo(b));
      return Scaffold(
        appBar: AppBar(
          title: const Text("Waypoints"),
          actions: [
            IconButton(
                iconSize: 30,
                onPressed: () {
                  editPlanName(context, null).then((value) {
                    if (value != null && value != "") {
                      var plan = FlightPlan(value);
                      Navigator.pushNamed(context, "/planEditor", arguments: plan);
                    }
                  });
                },
                icon: const Icon(Icons.add)),
            IconButton(iconSize: 30, onPressed: () => {savePlan(context)}, icon: const Icon(Icons.save_as)),
            IconButton(
                iconSize: 30, onPressed: () => {selectKmlImport(context)}, icon: const Icon(Icons.file_upload_outlined))
          ],
        ),
        body: plans.loadedPlans.isEmpty
            ? Center(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  // Padding(
                  //   padding: EdgeInsets.all(8.0),
                  //   child: Text("No plans created yet!"),
                  // ),
                  Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text("Use the buttons in the upper right corner to:", softWrap: true, maxLines: 3),
                  ),
                  Text("- Create a new plan / collection\n- Save the active plan\n- Import a KML file"),
                ],
              ))
            : ListView.builder(
                itemCount: plans.loadedPlans.length,
                itemBuilder: (context, index) => PlanCard(plans.loadedPlans[keys[index]]!),
              ),
      );
    }));
  }
}
