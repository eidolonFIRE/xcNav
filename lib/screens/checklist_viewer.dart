import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/models/checklist.dart';
import 'package:xcnav/providers/my_telemetry.dart';

class ChecklistViewer extends StatefulWidget {
  const ChecklistViewer({super.key});

  @override
  State<ChecklistViewer> createState() => _ChecklistViewerState();
}

class _ChecklistViewerState extends State<ChecklistViewer> {
  String? curChecklist;
  bool isEditing = false;
  final textEditor = TextEditingController();

  Map<String, Checklist> checklists = {};

  final Map<String, String> defaultChecklist = {
    "Preflight": """
      #Pack
      Water
      USB Battery

      #Plan Flight
      Briefed & Setup
      Check Weather

      #Inspect Motor
      Throttle Action
      Airbox Tight
      Exhaust Springs & Brackets
      Reserve Pins & Bridle

      #Prep Wing
      A's on top
      Stabilo on Outside
      Toggles to Pullies
      Trims to Launch Setting
    """,
    "Landing": """
      #Gear
      Buckles
      Luggage
      Trims

      #Plan Approach
      Measure Wind
      Check for Powerlines
    """,
  };

  @override
  void initState() {
    super.initState();

    getApplicationDocumentsDirectory().then((tempDir) {
      // Load default lists
      for (final listName in ["Preflight", "Landing"]) {
        final listPath = "${tempDir.path}/checklists/$listName.text";
        File listFile = File(listPath);
        if (listFile.existsSync()) {
          checklists[listName] = Checklist.fromText(listName, listPath, listFile.readAsStringSync());
        } else {
          // Load default
          checklists[listName] = Checklist.fromText(listName, listPath, defaultChecklist[listName]!);
        }
      }
      setState(() {
        if (Provider.of<MyTelemetry>(context, listen: false).inFlight) {
          curChecklist = "Landing";
        } else {
          curChecklist = "Preflight";
        }
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Checklist:",
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (!isEditing)
                DropdownButton<String>(
                    value: curChecklist,
                    items: checklists.keys.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    style: Theme.of(context).textTheme.bodyLarge,
                    onChanged: (value) {
                      setState(() {
                        curChecklist = value;
                      });
                    }),
              Container()
            ],
          ),
          actions: [
            IconButton(
                onPressed: () {
                  setState(() {
                    isEditing = !isEditing;
                    if (isEditing) {
                      // Prep editor
                      textEditor.text = checklists[curChecklist].toString();
                    } else {
                      // Save changes
                      String newText = textEditor.text;

                      // If document is empty, use default
                      if (newText.isEmpty) newText = defaultChecklist[curChecklist].toString();

                      if (newText != defaultChecklist[curChecklist].toString()) {
                        checklists[curChecklist!] =
                            Checklist.fromText(curChecklist!, checklists[curChecklist]!.filename, newText);
                        debugPrint("Saving checklist to: ${checklists[curChecklist]!.filename}");
                        File listFile = File(checklists[curChecklist]!.filename);
                        listFile
                            .create(recursive: true)
                            .then((file) => file.writeAsString(checklists[curChecklist].toString()));
                      }
                      textEditor.clear();
                    }
                  });
                },
                icon: Icon(isEditing ? Icons.save : Icons.edit))
          ],
        ),
        body: curChecklist != null
            ? (isEditing
                ?

                /// --- Editing
                Scrollbar(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextField(
                        style: const TextStyle(fontSize: 20),
                        decoration: const InputDecoration(
                            hintText: "#Catagory\nitem\nitem\nitem\n...", border: InputBorder.none),
                        autofocus: true,
                        minLines: 2,
                        maxLines: 99,
                        controller: textEditor,
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                      ),
                    ),
                  )

                /// --- Checklist
                : checklists[curChecklist]!.catagories.isEmpty
                    ? const Center(
                        child: Text(
                          "Wow, such empty!",
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      )
                    : ListView(
                        primary: true,
                        children: checklists[curChecklist]!
                            .catagories
                            .mapIndexed((cataIndex, cata) =>
                                <Widget>[
                                  // --- Section Header
                                  ListTile(
                                      key: Key("$cataIndex ${cata.title}"),
                                      // visualDensity: VisualDensity.compact,
                                      tileColor: Colors.amber,
                                      title: Text(
                                        cata.title,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, color: Colors.black, fontSize: 28),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            "${cata.items.where((e) => e.isChecked).length}/${cata.items.length}",
                                            style: TextStyle(color: Colors.black.withAlpha(170), fontSize: 16),
                                          ),
                                          Transform.scale(
                                            scale: 1.5,
                                            child: Checkbox(
                                              fillColor: WidgetStateProperty.resolveWith<Color>((states) =>
                                                  states.contains(WidgetState.selected)
                                                      ? Colors.black
                                                      : Colors.black.withAlpha(170)),
                                              checkColor: Colors.amber,
                                              value: cata.isChecked,
                                              onChanged: (value) {
                                                setState(() {
                                                  cata.isChecked = value ?? false;
                                                });
                                              },
                                            ),
                                          ),
                                        ],
                                      ))
                                ]
                                // --- Checkbox Items
                                +
                                (cata.isChecked
                                    ? [Container()]
                                    : cata.items
                                        .mapIndexed((itemIndex, item) => ListTile(
                                            key: Key(item.title),
                                            title: Text(
                                              item.title,
                                              style: Theme.of(context).textTheme.bodyLarge,
                                            ),
                                            trailing: Transform.scale(
                                              scale: 1.5,
                                              child: Checkbox(
                                                  value: item.isChecked,
                                                  fillColor: WidgetStateProperty.resolveWith<Color>((states) =>
                                                      states.contains(WidgetState.selected)
                                                          ? Colors.greenAccent
                                                          : Colors.black),
                                                  checkColor: Colors.black,
                                                  onChanged: (value) {
                                                    setState(() {
                                                      checklists[curChecklist]!
                                                          .catagories[cataIndex]
                                                          .items[itemIndex]
                                                          .isChecked = value ?? false;
                                                    });
                                                  }),
                                            )))
                                        .toList()))
                            .reduce((a, b) => a + b)))
            : const Center(child: CircularProgressIndicator.adaptive()));
  }
}
