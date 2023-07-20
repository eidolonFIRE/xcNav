import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

class SelectedFoldersOptions {
  final List<XmlElement> folders;
  SelectedFoldersOptions(this.folders);
}

Future<SelectedFoldersOptions?> selectKmlFolders(BuildContext context, List<XmlElement> folders) {
  return showDialog<SelectedFoldersOptions>(
      context: context,
      builder: (context) {
        Set<int> checkedElements = {};
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            insetPadding: EdgeInsets.all(10),
            title: const Text("Select KML Folders"),
            actions: [
              IconButton(
                  onPressed: () {
                    // Return list of selected folders
                    Navigator.pop(context, SelectedFoldersOptions(checkedElements.map((e) => folders[e]).toList()));
                  },
                  icon: const Icon(
                    Icons.check,
                    color: Colors.lightGreen,
                  ))
            ],
            content: Container(
              width: MediaQuery.of(context).size.width - 10,
              child: ListView.builder(
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
            ),
          );
        });
      });
}
