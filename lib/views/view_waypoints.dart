import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

// --- Dialogs
import 'package:xcnav/dialogs/save_plan.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/plans.dart';

// --- Widgets
import 'package:xcnav/widgets/waypoint_card.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

// --- Misc
import 'package:xcnav/dialogs/edit_waypoint.dart';

// --- Models
import 'package:xcnav/models/waypoint.dart';

class ViewWaypoints extends StatefulWidget {
  const ViewWaypoints({super.key});

  @override
  State<ViewWaypoints> createState() => ViewWaypointsState();
}

class ViewWaypointsState extends State<ViewWaypoints> {
  final filterText = TextEditingController();
  final textFocusNode = FocusNode();
  String? filterIcon;
  Color? filterColor;
  bool filterDist = true;

  int compareColor(Color a, Color b) {
    return (a.blue - b.blue).abs() + (a.red - b.red).abs() + (a.green - b.green).abs();
  }

  int compareWaypoints(Waypoint a, Waypoint b) {
    // Weights for different factors of the fuzzy sort
    const iconWeight = 1000;
    const colorWeight = 2;
    const distWeight = 0.004;
    const textWeight = 60;
    const emphemeralWeight = 2000;

    int retval = 0;
    if (filterText.text.isNotEmpty) {
      retval += (weightedRatio(b.name.toLowerCase(), filterText.text) -
              weightedRatio(a.name.toLowerCase(), filterText.text)) *
          textWeight;
    }
    retval += a.ephemeral ? emphemeralWeight : 0;
    retval -= b.ephemeral ? emphemeralWeight : 0;
    if (filterIcon != null) {
      if (filterIcon == "PATH") {
        retval += b.isPath ? iconWeight : 0;
        retval -= a.isPath ? iconWeight : 0;
      } else {
        retval += ratio(a.name, filterText.text) +
            (b.icon == filterIcon ? iconWeight : 0) -
            (a.icon == filterIcon ? iconWeight : 0);
      }
    }
    if (filterColor != null) {
      retval +=
          ((compareColor(a.getColor(), filterColor!) - compareColor(b.getColor(), filterColor!)) * colorWeight).toInt();
    }
    final geo = Provider.of<MyTelemetry>(context, listen: false).geo;
    if (filterDist && geo != null) {
      retval +=
          ((geo.getIntercept(a.latlngOriented).dist - geo.getIntercept(b.latlngOriented).dist) * distWeight).round();
    }
    return retval;
  }

  Future<String?>? showIconPicker(BuildContext context) {
    return showDialog<String?>(
        context: context,
        builder: (context) => Builder(builder: (context) {
              // --- Build icon selection buttons
              List<Widget> iconWidgets = [];

              for (final name in (iconOptions.keys.toList() + ["PATH"])) {
                iconWidgets.add(IconButton(
                  onPressed: () => {Navigator.pop(context, name)},
                  padding: const EdgeInsets.all(0),
                  iconSize: 50,
                  color: Colors.white,
                  icon: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: getWpIcon(name, 30, Colors.white),
                  ),
                ));
              }

              return AlertDialog(
                  content: SizedBox(
                width: MediaQuery.of(context).size.width - 100,
                height: MediaQuery.of(context).size.height / 3,
                child: Card(
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.background,
                  child: GridView.count(
                    crossAxisCount: 5,
                    shrinkWrap: true,
                    children: iconWidgets,
                  ),
                ),
              ));
            }));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ActivePlan>(builder: (context, activePlan, child) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Waypoint menu buttons
          SizedBox(
            height: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // --- Filter Color
                DropdownButtonHideUnderline(
                  child: DropdownButton<Color?>(
                      value: filterColor,
                      items: [
                        const DropdownMenuItem<Color?>(
                            value: null,
                            child: Padding(
                              padding: EdgeInsets.only(left: 15),
                              child: Icon(Icons.palette),
                            )),
                        ...colorOptions.values.map((e) => DropdownMenuItem<Color?>(
                            value: e,
                            child: Card(
                              color: e,
                              child: const SizedBox(width: 40, height: 30),
                            )))
                      ],
                      onChanged: ((value) {
                        setState(() {
                          filterColor = value;
                        });
                      })),
                ),

                // --- Filter Icon
                IconButton(
                    onPressed: () {
                      showIconPicker(context)?.then((value) {
                        setState(() {
                          filterIcon = value;
                        });
                      });
                    },
                    icon: getWpIcon(filterIcon, 25, Colors.white)),

                // --- Filter Text
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 40),
                    child: TextField(
                      autofocus: false,
                      focusNode: textFocusNode,
                      style: const TextStyle(fontSize: 20),
                      controller: filterText,
                      decoration: InputDecoration(
                          contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                          hintText: "search"),
                      onChanged: (value) {
                        setState(() {
                          // (this will make the waypoint list re-sort)
                          // debugPrint("FilterText ${filterText.text}");
                        });
                      },
                    ),
                  ),
                ),

                // --- Clear Search
                IconButton(
                    onPressed: () {
                      setState(() {
                        filterText.clear();
                        filterIcon = null;
                        filterColor = null;
                        textFocusNode.unfocus();
                      });
                    },
                    icon: const Icon(
                      Icons.cancel,
                      color: Colors.red,
                    )),

                // --- Divider
                const SizedBox(
                  height: 40,
                  child: VerticalDivider(
                    color: Colors.grey,
                    thickness: 1,
                    width: 10,
                  ),
                ),

                // --- Menu
                PopupMenuButton<String>(
                    key: const Key("viewWaypoints_moreOptions"),
                    onSelected: (value) {
                      switch (value) {
                        case "library":
                          Navigator.pushNamed(context, "/plans");
                          break;
                        case "save":
                          savePlan(context);
                          break;
                        case "clear":
                          showDialog(
                              context: context,
                              builder: (BuildContext ctx) {
                                return AlertDialog(
                                  title: const Text('Are you sure?'),
                                  content: const Text('This will clear all waypoints for everyone in the group!'),
                                  actions: [
                                    TextButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pop(true);
                                        },
                                        icon: const Icon(
                                          Icons.delete_forever,
                                          color: Colors.red,
                                        ),
                                        label: const Text('Clear')),
                                    TextButton(
                                        onPressed: () {
                                          // Close the dialog
                                          Navigator.of(context).pop(false);
                                        },
                                        child: const Text('Cancel'))
                                  ],
                                );
                              }).then((value) {
                            if (value) {
                              activePlan.clearAllWayponits();
                              Provider.of<Client>(context, listen: false).pushWaypoints();
                            }
                          });
                          break;
                      }
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                          PopupMenuItem(
                              value: "library",
                              child: ListTile(leading: Icon(Icons.bookmarks), title: Text("Library"))),
                          PopupMenuItem(
                            value: "save",
                            child: ListTile(
                              leading: Icon(
                                Icons.save_as,
                                color: Colors.green,
                              ),
                              title: Text("Save"),
                            ),
                          ),
                          PopupMenuItem(
                            value: "clear",
                            child: ListTile(
                              leading: Icon(
                                Icons.delete_forever,
                                color: Colors.red,
                              ),
                              title: Text("Clear"),
                            ),
                          ),
                        ]),
              ],
            ),
          ),

          // --- Waypoint list
          if (activePlan.waypoints.isNotEmpty)
            Expanded(
              child: Builder(builder: (context) {
                final items = activePlan.waypoints.values.toList();
                items.sort(compareWaypoints);
                return ListView.builder(
                  // primary: true,
                  itemCount: items.length,
                  itemBuilder: (context, i) => Slidable(
                    key: ValueKey(items[i]),
                    dragStartBehavior: DragStartBehavior.start,
                    startActionPane: ActionPane(extentRatio: 0.15, motion: const ScrollMotion(), children: [
                      SlidableAction(
                        onPressed: (e) => {activePlan.removeWaypoint(items[i].id)},
                        icon: Icons.delete,
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ]),
                    endActionPane: ActionPane(
                      extentRatio: 0.3,
                      motion: const ScrollMotion(),
                      children: [
                        SlidableAction(
                          onPressed: (e) {
                            editWaypoint(
                              context,
                              items[i],
                            )?.then((newWaypoint) {
                              if (newWaypoint != null) {
                                // --- Update selected waypoint
                                Provider.of<ActivePlan>(context, listen: false).updateWaypoint(newWaypoint);
                              }
                            });
                          },
                          icon: Icons.edit,
                          backgroundColor: Colors.grey.shade400,
                          foregroundColor: Colors.black,
                        ),
                        SlidableAction(
                          onPressed: (e) {
                            showDialog<String>(
                                context: context,
                                builder: (context) => SimpleDialog(
                                      title: Text(Provider.of<Plans>(context, listen: false).loadedPlans.isEmpty
                                          ? "Oops, make a collection in Waypoints menu first!"
                                          : "Save waypoint into:"),
                                      children: Provider.of<Plans>(context, listen: false)
                                          .loadedPlans
                                          .keys
                                          .map((name) => SimpleDialogOption(
                                              onPressed: () => Navigator.pop(context, name), child: Text(name)))
                                          .toList(),
                                    )).then((value) {
                              if (value != null) {
                                Provider.of<Plans>(context, listen: false).loadedPlans[value]?.waypoints[items[i].id] =
                                    Waypoint.from(items[i]);
                              }
                            });
                          },
                          icon: Icons.playlist_add,
                          backgroundColor: Colors.grey.shade400,
                          foregroundColor: Colors.black,
                        )
                      ],
                    ),
                    child: WaypointCard(
                      waypoint: items[i],
                      index: i,
                      refLatlng: Provider.of<MyTelemetry>(context, listen: false).geo?.latlng,
                      onSelect: () {
                        debugPrint("Selected ${items[i].id} (prev: ${activePlan.selectedWp}");
                        if (activePlan.selectedWp == items[i].id) {
                          // Deselect
                          activePlan.selectedWp = null;
                        } else {
                          activePlan.selectedWp = items[i].id;
                        }
                      },
                      isSelected: items[i].id == activePlan.selectedWp,
                    ),
                  ),
                );
              }),
            ),
          // This shows when flight plan is empty
          if (activePlan.waypoints.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 50, bottom: 50),
              child: Text(
                "No waypoints added yet... \n\nLong-press on the map to begin.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      );
    });
  }
}
