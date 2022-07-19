import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

Future<List<XmlElement>?> selectKmlFolders(BuildContext context, List<XmlElement> folders) {
  return showDialog<List<XmlElement>>(
      context: context,
      builder: (context) {
        Set<int> checkedElements = {};
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text("Select KML Folders"),
            actions: [
              IconButton(
                  onPressed: () {
                    // Return list of selected folders
                    Navigator.pop(context, checkedElements.map((e) => folders[e]).toList());
                  },
                  icon: const Icon(
                    Icons.check,
                    color: Colors.lightGreen,
                  ))
            ],
            content: ListView.builder(
              shrinkWrap: true,
              itemCount: folders.length,
              itemBuilder: (context, index) => ListTile(
                // contentPadding: EdgeInsets.zero,
                leading: Checkbox(
                  onChanged: (checked) {
                    setState(
                      () {
                        if (checked ?? false) {
                          checkedElements.add(index);
                        } else {
                          checkedElements.remove(index);
                        }
                      },
                    );
                  },
                  value: checkedElements.contains(index),
                ),
                title: Text(
                  folders[index].findElements("name").first.innerText,
                  softWrap: true,
                  maxLines: 3,
                ),
              ),
            ),
          );
        });
      });
}
