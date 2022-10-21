import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

// --- Dialogs
import 'package:xcnav/dialogs/save_plan.dart';
import 'package:xcnav/models/geo.dart';

// --- Providers
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/icon_image.dart';
import 'package:xcnav/widgets/map_marker.dart';

// --- Widgets
import 'package:xcnav/widgets/waypoint_card.dart';

// --- Misc
import 'package:xcnav/dialogs/edit_waypoint.dart';
import 'package:xcnav/screens/home.dart';

// --- Models
import 'package:xcnav/models/waypoint.dart';

class ViewWaypoints extends StatefulWidget {
  const ViewWaypoints({Key? key}) : super(key: key);

  @override
  State<ViewWaypoints> createState() => ViewWaypointsState();
}

class ViewWaypointsState extends State<ViewWaypoints> {
  final filterText = TextEditingController();
  String? filterIcon;
  Color? filterColor;
  bool filterDist = false;

  int compareColor(Color a, Color b) {
    return (a.blue - b.blue).abs() + (a.red - b.red).abs() + (a.green - b.green).abs();
  }

  int compareWaypoints(Waypoint a, Waypoint b) {
    // Weights for different factors of the fuzzy sort
    const iconWeight = 50;
    const colorWeight = 0.1;
    const distWeight = 0.001;

    int retval = ratio(b.name, filterText.text) - ratio(a.name, filterText.text);
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
    if (filterDist) {
      final refLatlng = Provider.of<MyTelemetry>(context, listen: false).geo.latLng;
      retval +=
          ((latlngCalc.distance(refLatlng, a.latlng[0]) - latlngCalc.distance(refLatlng, b.latlng[0])) * distWeight)
              .round();
    }
    return retval;
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
                // --- Filter Distance
                Switch(
                  value: filterDist,
                  inactiveThumbImage: IconImageProvider(Icons.straighten),
                  activeThumbImage: IconImageProvider(Icons.straighten, color: Colors.black),
                  onChanged: (value) {
                    setState(() {
                      filterDist = value;
                    });
                  },
                ),

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
                              child: const SizedBox(width: 50, height: 30),
                            )))
                      ],
                      onChanged: ((value) {
                        setState(() {
                          filterColor = value;
                        });
                      })),
                ),

                // --- Filter Icon
                DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                      value: filterIcon,
                      items: [
                        DropdownMenuItem<String?>(
                            value: "PATH",
                            child: SizedBox(
                                width: 28,
                                height: 28,
                                child: SvgPicture.asset(
                                  "assets/images/path.svg",
                                  color: Colors.white,
                                ))),
                        const DropdownMenuItem<String?>(value: null, child: Icon(Icons.circle_outlined)),
                        ...iconOptions.keys
                            .where((element) => element != null)
                            .map((e) => DropdownMenuItem<String?>(value: e, child: getWpIcon(e, 25, Colors.white)))
                      ],
                      onChanged: ((value) {
                        setState(() {
                          filterIcon = value;
                        });
                      })),
                ),

                // --- Filter Text
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 40),
                    child: TextField(
                      style: const TextStyle(fontSize: 20),
                      textAlignVertical: TextAlignVertical.bottom,
                      controller: filterText,
                      decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                          // border: InputBorder.none,
                          // contentPadding: const EdgeInsets.all(8)),
                          hintText: "text"),
                      onChanged: (value) {
                        setState(() {
                          debugPrint("FilterText ${filterText.text}");
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
                    onSelected: (value) {
                      switch (value) {
                        case "library":
                          Navigator.pushNamed(context, "/plans");
                          break;
                        case "save":
                          Navigator.pop(context);
                          savePlan(context);
                          break;
                        case "clear":
                          showDialog(
                              context: context,
                              builder: (BuildContext ctx) {
                                return AlertDialog(
                                  title: const Text('Are you sure?'),
                                  content: const Text('This will clear the flight plan for everyone in the group!'),
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
                              activePlan.waypoints.clear();
                              Provider.of<Client>(context, listen: false).pushFlightPlan();
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
                              leading: Icon(Icons.save_as),
                              title: Text("Save Plan"),
                            ),
                          ),
                          PopupMenuItem(
                            value: "clear",
                            child: ListTile(
                              leading: Icon(
                                Icons.delete_forever,
                                color: Colors.red,
                              ),
                              title: Text("Clear Waypoints"),
                            ),
                          ),
                        ]),
              ],
            ),
          ),

          // --- Waypoint list
          Expanded(
            child: Builder(builder: (context) {
              final items = activePlan.waypoints.toList();
              items.sort(compareWaypoints);
              return ListView.builder(
                // shrinkWrap: true,
                // primary: true,
                itemCount: items.length,
                itemBuilder: (context, i) => Slidable(
                  key: ValueKey(items[i]),
                  dragStartBehavior: DragStartBehavior.start,
                  startActionPane: ActionPane(extentRatio: 0.15, motion: const ScrollMotion(), children: [
                    SlidableAction(
                      onPressed: (e) => {activePlan.removeWaypoint(i)},
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
                            // TODO
                            // editPointsCallback: () => onEditPoints(i),
                          )?.then((newWaypoint) {
                            if (newWaypoint != null) {
                              // --- Update selected waypoint
                              Provider.of<ActivePlan>(context, listen: false).updateWaypoint(
                                  i, newWaypoint.name, newWaypoint.icon, newWaypoint.color, newWaypoint.latlng);
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
                                        ? "Oops, make a plan / collection in Waypoints menu first!"
                                        : "Save waypoint into:"),
                                    children: Provider.of<Plans>(context, listen: false)
                                        .loadedPlans
                                        .keys
                                        .map((name) => SimpleDialogOption(
                                            onPressed: () => Navigator.pop(context, name), child: Text(name)))
                                        .toList(),
                                  )).then((value) {
                            if (value != null) {
                              Provider.of<Plans>(context, listen: false).loadedPlans[value]?.waypoints.add(items[i]);
                            }
                          });
                        },
                        icon: Icons.playlist_add,
                        backgroundColor: Colors.grey.shade400,
                        foregroundColor: Colors.black,
                      )
                      // ReorderableDragStartListener(
                      //   index: i,
                      //   child: Container(
                      //     color: Colors.grey.shade400,
                      //     child: const Padding(
                      //       padding: EdgeInsets.all(16.0),
                      //       child: Icon(
                      //         Icons.drag_handle,
                      //         size: 24,
                      //         color: Colors.black,
                      //       ),
                      //     ),
                      //   ),
                      // ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // TODO: use nearest point (better for paths)
                      Container(
                        constraints: const BoxConstraints(minWidth: 40),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Text.rich(
                            richValue(
                                UnitType.distCoarse,
                                latlngCalc(
                                    items[i].latlng[0], Provider.of<MyTelemetry>(context, listen: false).geo.latLng),
                                valueStyle: const TextStyle(fontSize: 18),
                                unitStyle:
                                    const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 12)),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ),
                      Expanded(
                        child: WaypointCard(
                          waypoint: items[i],
                          index: i,
                          onSelect: () {
                            debugPrint("Selected $i");
                            activePlan.selectWaypoint(i);
                          },
                          // onDoubleTap: () {
                          //   zoomMainMapToLatLng.sink.add(items[i].latlng[0]);
                          // },
                          isSelected: i == activePlan.selectedIndex,
                        ),
                      ),
                    ],
                  ),
                ),
                // onReorder: (oldIndex, newIndex) {
                //   debugPrint("WP order: $oldIndex --> $newIndex");
                //   activePlan.sortWaypoint(oldIndex, newIndex);
                //   Provider.of<Group>(context, listen: false).fixPilotSelectionsOnSort(oldIndex, newIndex);
                // },
              );
            }),
          ),
          // This shows when flight plan is empty
          if (activePlan.waypoints.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 50, bottom: 50),
              child: Text(
                "No waypoints added yet...",
                textAlign: TextAlign.center,
                style: instrLabel,
              ),
            ),
        ],
      );
    });
  }
}
