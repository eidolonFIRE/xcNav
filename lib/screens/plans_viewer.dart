import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/dialogs/edit_plan_name.dart';

// --- Dialogs
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
  void selectKmlImport(BuildContext context, Plans plans) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ["kml"]);

    if (result != null) {
      File file = File(result.files.single.path!);
      file.readAsString().then((data) async {
        final document = XmlDocument.parse(data).getElement("kml")!.getElement("Document")!;

        // Select which folders to import
        final folderNames = document.findAllElements("Folder").toList();

        final selectedFolderOptions = await selectKmlFolders(context, folderNames);
        final selectedFolders = folderNames.isNotEmpty ? selectedFolderOptions?.folders : null;
        final newPlan = FlightPlan.fromKml(result.files.single.name, document, selectedFolders ?? []);
        plans.setPlan(newPlan);
      });
    } else {
      // User canceled the picker
    }
  }

  void iFlightURL(BuildContext context, String? initialClipText) async {
    // final urlController = TextEditingController(text: (await Clipboard.getData("text/plain"))?.text);
    // final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // final initialClipText = ;

    FlightPlan parsePlan(String name, String url) {
      debugPrint("----");
      final uri = Uri.parse(url);
      final route = uri.queryParameters["Route"] ?? "";
      return FlightPlan.fromiFlightPlanner(name, route);
    }

    // if (urlController.text.isNotEmpty) parsePlan();

    String? name;
    String? url;

    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("iFlightPlanner"),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const Key("iFlightPlannerName"),
                      autofocus: true,
                      // controller: nameController,
                      decoration: const InputDecoration(hintText: "Plan Name"),
                      validator: (value) {
                        if (value?.isEmpty ?? true) {
                          return "Must not be empty.";
                        }
                        return null;
                      },
                      onChanged: (value) {
                        formKey.currentState?.validate();
                      },
                      onSaved: (newValue) => name = newValue,
                    ),
                    TextFormField(
                      key: const Key("iFlightPlannerURL"),
                      // controller: urlController,
                      initialValue: initialClipText,
                      decoration: const InputDecoration(hintText: "URL"),
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      validator: (value) {
                        if (value?.isEmpty ?? false) {
                          return "Must not be empty.";
                        }
                        final plan = parsePlan("-", value!);
                        if (!plan.goodFile) {
                          return "Error Parsing.";
                        }
                        return null;
                      },
                      onChanged: (url) {
                        formKey.currentState?.validate();
                      },
                      onSaved: (newValue) => url = newValue,
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton.icon(
                    onPressed: () {
                      formKey.currentState?.save();
                      if ((formKey.currentState?.validate() ?? false) && name != null && url != null) {
                        final plan = parsePlan(name!, url!);
                        Provider.of<Plans>(context, listen: false).setPlan(plan);
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(
                      Icons.check,
                      color: Colors.lightGreen,
                    ),
                    label: const Text("Load"))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<Plans>(builder: ((context, plans, child) {
      var keys = plans.loadedPlans.keys.toList();
      keys.sort((a, b) => a.compareTo(b));
      return Scaffold(
        appBar: AppBar(
          title: const Text("Library"),
          actions: [
            PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case "new":
                      editPlanName(context, null).then((value) {
                        if (value != null && value != "") {
                          var plan = FlightPlan(value);
                          Navigator.pushNamed(context, "/planEditor", arguments: plan);
                        }
                      });
                      break;
                    case "kml":
                      selectKmlImport(context, Provider.of<Plans>(context, listen: false));
                      break;
                    case "iFlight":
                      Clipboard.getData("text/plain").then(
                        (value) {
                          iFlightURL(context, value?.text);
                        },
                      );
                      break;
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem(
                          value: "new",
                          child: ListTile(
                            leading: Icon(
                              Icons.add,
                              color: Colors.lightGreen,
                            ),
                            title: Text("New"),
                          )),
                      const PopupMenuItem(
                          value: "kml",
                          child: ListTile(
                            leading: Icon(
                              Icons.file_upload_outlined,
                              color: Colors.lightBlue,
                            ),
                            title: Text("Import KML"),
                          )),
                      PopupMenuItem(
                          value: "iFlight",
                          child: ListTile(
                            leading: SvgPicture.asset(
                              "assets/external/iFlightPlanner-Mark-White.svg",
                              color: Colors.white,
                              height: 24,
                            ),
                            title: const Text("iFlightPlanner URL"),
                          ))
                    ]),
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
                  Text("- Create a collection\n- Save the active set of waypoints\n- Import a KML file"),
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
